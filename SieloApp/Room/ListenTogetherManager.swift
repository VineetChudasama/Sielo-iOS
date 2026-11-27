import Foundation
import CocoaMQTT
import CoreImage.CIFilterBuiltins
import UIKit
import SieloCoreModels
import SieloCoreAudio

/// Mirrors app/room/manager/ListenTogetherManager.kt:
/// MQTT E2EE rooms (sielo/v3/rooms/{ROOM_ID}), sub-150ms drift compensation, host failover, and QR invite generation.
@MainActor
public final class ListenTogetherManager: ObservableObject {
    @Published public private(set) var roomState: ActiveRoomState?
    @Published public private(set) var pendingRejoinSession: SavedRoomSession?
    @Published public var roomNotification: String?

    private let playerManager: PlayerManager
    private let prefs = UserDefaults(suiteName: "sielo_room_session_prefs") ?? .standard
    private let brokers = ["broker.emqx.io", "broker.hivemq.com"]

    private var mqtt: CocoaMQTT?
    private var currentTopic: String?
    private var hostHeartbeatTask: Task<Void, Never>?
    private var driftCheckTask: Task<Void, Never>?
    private var hostSequenceNumber: Int64 = 0
    private var lastAppliedSequence: Int64 = 0
    private var lastHostPacketAt: Date = Date()
    private var lastAuthPositionMs: Int64 = 0
    private var lastAuthTimestampMs: Int64 = 0
    private var lastAuthIsPlaying: Bool = false
    private var lastHardSyncAt: Date = .distantPast

    public init(playerManager: PlayerManager) {
        self.playerManager = playerManager
        checkPendingRejoinSession()
    }

    // MARK: - Room Creation & Joining

    public func createRoom(userName: String) {
        let roomId = generateRoomId()
        let roomKey = RoomCrypto.deriveKey(roomId: roomId)
        let localId = UUID().uuidString
        let cleanName = userName.isEmpty ? "Host" : userName

        let host = RoomParticipant(id: localId, name: cleanName, isHost: true, joinedAt: nowMs())
        roomState = ActiveRoomState(
            roomId: roomId,
            roomKey: roomKey,
            localUserId: localId,
            localUserName: cleanName,
            isHost: true,
            participants: [host],
            queue: [],
            currentTrack: playerManager.playbackState.currentTrack,
            isPlaying: playerManager.playbackState.isPlaying,
            positionMs: playerManager.playbackState.currentPositionMs,
            messages: [],
            typingUsers: [:],
            connectionState: .connecting
        )
        saveSession(roomId: roomId, roomKey: roomKey, userName: cleanName, isHost: true)
        connectMQTT(roomId: roomId, roomKey: roomKey)
    }

    public func joinRoom(rawInput: String, keyOverride: String = "", userName: String) -> Bool {
        guard let roomId = extractRoomId(from: rawInput) else { return false }
        let roomKey = keyOverride.isEmpty ? RoomCrypto.deriveKey(roomId: roomId) : keyOverride
        let localId = UUID().uuidString
        let cleanName = userName.isEmpty ? "Listener" : userName

        let me = RoomParticipant(id: localId, name: cleanName, isHost: false, joinedAt: nowMs())
        roomState = ActiveRoomState(
            roomId: roomId,
            roomKey: roomKey,
            localUserId: localId,
            localUserName: cleanName,
            isHost: false,
            participants: [me],
            queue: [],
            currentTrack: nil,
            isPlaying: false,
            positionMs: 0,
            messages: [],
            typingUsers: [:],
            connectionState: .connecting
        )
        saveSession(roomId: roomId, roomKey: roomKey, userName: cleanName, isHost: false)
        connectMQTT(roomId: roomId, roomKey: roomKey)
        return true
    }

    public func leaveRoom(intentional: Bool = true) {
        if let state = roomState {
            publishEvent(RoomEvent(type: "leave", senderId: state.localUserId, senderName: state.localUserName), qos: .qos1)
        }
        hostHeartbeatTask?.cancel()
        driftCheckTask?.cancel()
        mqtt?.disconnect()
        mqtt = nil
        roomState = nil
        playerManager.clearListenTogetherScope()
        if intentional {
            prefs.removeObject(forKey: "saved_room_session")
            pendingRejoinSession = nil
        }
    }

    // MARK: - Room Actions (Chat, Queue, Playback)

    public func sendChatMessage(_ text: String, replyTo: RoomChatMessage? = nil) {
        guard var state = roomState, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let msg = RoomChatMessage(
            id: UUID().uuidString,
            senderId: state.localUserId,
            senderName: state.localUserName,
            text: text,
            timestamp: nowMs(),
            isHost: state.isHost,
            isSystemEvent: false,
            replyToText: replyTo?.text,
            replyToSender: replyTo?.senderName
        )
        state.messages.append(msg)
        roomState = state
        publishEvent(RoomEvent(type: "chat", senderId: state.localUserId, senderName: state.localUserName, message: msg), qos: .qos0)
    }

    public func addToQueue(_ track: SieloTrack) {
        guard var state = roomState else { return }
        let item = RoomQueueItem(id: UUID().uuidString, track: track, addedBy: state.localUserName, addedAt: nowMs())
        state.queue.append(item)
        roomState = state
        playerManager.updateListenTogetherQueue(state.queue.map(\.track))
        publishEvent(RoomEvent(type: "queue_add", senderId: state.localUserId, senderName: state.localUserName, queue: [item]), qos: .qos1)
    }

    public func togglePlayPause() {
        guard let state = roomState else { return }
        let nextPlaying = !state.isPlaying
        let action = nextPlaying ? "PLAY" : "PAUSE"
        if state.isHost {
            nextPlaying ? playerManager.play() : playerManager.pause()
            hostSequenceNumber += 1
            publishEvent(RoomEvent(
                type: "playback",
                senderId: state.localUserId,
                senderName: state.localUserName,
                sequenceNumber: hostSequenceNumber,
                action: action,
                positionMs: playerManager.playbackState.currentPositionMs,
                isPlaying: nextPlaying
            ), qos: .qos1)
        } else {
            publishEvent(RoomEvent(
                type: "playback",
                senderId: state.localUserId,
                senderName: state.localUserName,
                sequenceNumber: 0,
                action: action
            ), qos: .qos1)
        }
    }

    // MARK: - QR Code Generation

    public static func generateQRCode(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"
        guard let outputImage = filter.outputImage else { return nil }
        let colorFilter = CIFilter.falseColor()
        colorFilter.inputImage = outputImage
        colorFilter.color0 = CIColor(red: 250/255, green: 240/255, blue: 202/255) // Cream
        colorFilter.color1 = CIColor(red: 13/255, green: 19/255, blue: 33/255)    // Dark Navy
        guard let colored = colorFilter.outputImage else { return nil }
        let transformed = colored.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - MQTT & Drift Compensation

    private func connectMQTT(roomId: String, roomKey: String) {
        let clientId = "Sielo_iOS_\(UUID().uuidString.prefix(8))"
        let topic = "sielo/v3/rooms/\(roomId)"
        self.currentTopic = topic

        let client = CocoaMQTT(clientID: clientId, host: brokers[0], port: 1883)
        client.keepAlive = 30
        client.cleanSession = true
        client.autoReconnect = true

        if let state = roomState {
            let lwtEvent = RoomEvent(type: "leave", senderId: state.localUserId, senderName: state.localUserName)
            if let encoded = try? JSONEncoder().encode(lwtEvent),
               let jsonStr = String(data: encoded, encoding: .utf8),
               let encrypted = RoomCrypto.encrypt(plaintext: jsonStr, base64Key: roomKey) {
                client.willMessage = CocoaMQTTMessage(topic: topic, string: encrypted, qos: .qos1)
            }
        }

        client.didConnectAck = { [weak self] mqttClient, ack in
            guard ack == .accept, let self else { return }
            mqttClient.subscribe(topic, qos: .qos1)
            Task { @MainActor in
                self.roomState?.connectionState = .connected
                if let s = self.roomState {
                    self.publishEvent(RoomEvent(type: "join", senderId: s.localUserId, senderName: s.localUserName), qos: .qos1)
                    if s.isHost {
                        self.startHostHeartbeat()
                    } else {
                        self.publishEvent(RoomEvent(type: "request_sync", senderId: s.localUserId, senderName: s.localUserName), qos: .qos1)
                        self.startGuestDriftMonitor()
                    }
                }
            }
        }

        client.didReceiveMessage = { [weak self] _, message, _ in
            guard let payload = message.string, let self else { return }
            Task { @MainActor in
                self.handleIncomingPayload(payload)
            }
        }

        _ = client.connect()
        self.mqtt = client
    }

    private func publishEvent(_ event: RoomEvent, qos: CocoaMQTTQoS) {
        guard let state = roomState,
              let topic = currentTopic,
              let data = try? JSONEncoder().encode(event),
              let jsonStr = String(data: data, encoding: .utf8),
              let encrypted = RoomCrypto.encrypt(plaintext: jsonStr, base64Key: state.roomKey) else { return }
        mqtt?.publish(topic, withString: encrypted, qos: qos, retained: false)
    }

    private func handleIncomingPayload(_ payload: String) {
        guard let state = roomState,
              let jsonStr = RoomCrypto.decrypt(payload: payload, base64Key: state.roomKey),
              let data = jsonStr.data(using: .utf8),
              let event = try? JSONDecoder().decode(RoomEvent.self, from: data) else { return }

        guard event.senderId != state.localUserId else { return }
        lastHostPacketAt = Date()

        switch event.type {
        case "join":
            if !state.participants.contains(where: { $0.id == event.senderId }) {
                roomState?.participants.append(RoomParticipant(id: event.senderId, name: event.senderName, isHost: false, joinedAt: event.timestamp))
            }
        case "leave":
            roomState?.participants.removeAll { $0.id == event.senderId }
            checkHostFailoverIfNeeded(leftUserId: event.senderId)
        case "chat":
            if let msg = event.message {
                roomState?.messages.append(msg)
            }
        case "queue_add":
            if let added = event.queue {
                roomState?.queue.append(contentsOf: added)
                if let q = roomState?.queue {
                    playerManager.updateListenTogetherQueue(q.map(\.track))
                }
            }
        case "sync_state", "playback":
            if event.sequenceNumber > 0 && event.sequenceNumber >= lastAppliedSequence {
                lastAppliedSequence = event.sequenceNumber
                lastAuthPositionMs = event.positionMs ?? 0
                lastAuthTimestampMs = event.timestamp
                lastAuthIsPlaying = event.isPlaying ?? false
                roomState?.isPlaying = lastAuthIsPlaying
                if let track = event.track, playerManager.playbackState.currentTrack?.id != track.id {
                    roomState?.currentTrack = track
                    let q = roomState?.queue.map(\.track) ?? [track]
                    playerManager.playListenTogether(track: track, queue: q, seekToMs: lastAuthPositionMs, autoPlay: lastAuthIsPlaying)
                }
            }
        default:
            break
        }
    }

    private func startHostHeartbeat() {
        hostHeartbeatTask?.cancel()
        hostHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let s = self.roomState, s.isHost else { return }
                self.hostSequenceNumber += 1
                self.publishEvent(RoomEvent(
                    type: "sync_state",
                    senderId: s.localUserId,
                    senderName: s.localUserName,
                    sequenceNumber: self.hostSequenceNumber,
                    positionMs: self.playerManager.playbackState.currentPositionMs,
                    isPlaying: self.playerManager.playbackState.isPlaying,
                    track: self.playerManager.playbackState.currentTrack,
                    queue: s.queue,
                    participants: s.participants
                ), qos: .qos0)
            }
        }
    }

    private func startGuestDriftMonitor() {
        driftCheckTask?.cancel()
        driftCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, let s = self.roomState, !s.isHost else { return }

                // 18s host silence failover
                if Date().timeIntervalSince(self.lastHostPacketAt) > 18 {
                    if let hostId = s.participants.first(where: \.isHost)?.id {
                        self.checkHostFailoverIfNeeded(leftUserId: hostId)
                    }
                }

                guard self.lastAuthIsPlaying else { continue }
                let elapsed = self.nowMs() - self.lastAuthTimestampMs
                let expectedPos = self.lastAuthPositionMs + elapsed
                let drift = abs(expectedPos - self.playerManager.playbackState.currentPositionMs)

                if drift > 750 && Date().timeIntervalSince(self.lastHardSyncAt) > 1.5 {
                    self.lastHardSyncAt = Date()
                    self.playerManager.seekTo(expectedPos)
                }
            }
        }
    }

    private func checkHostFailoverIfNeeded(leftUserId: String) {
        guard var state = roomState else { return }
        guard let oldHostIdx = state.participants.firstIndex(where: { $0.id == leftUserId && $0.isHost }) else { return }
        state.participants[oldHostIdx].isHost = false
        if let nextHost = state.participants.min(by: { $0.joinedAt < $1.joinedAt }) {
            if let idx = state.participants.firstIndex(where: { $0.id == nextHost.id }) {
                state.participants[idx].isHost = true
            }
            if nextHost.id == state.localUserId {
                state.isHost = true
                startHostHeartbeat()
            }
        }
        roomState = state
    }

    // MARK: - Helpers & Session Persistence

    private func generateRoomId() -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let digits = Array("23456789")
        return String([
            letters.randomElement()!, digits.randomElement()!,
            letters.randomElement()!, digits.randomElement()!,
            letters.randomElement()!, digits.randomElement()!
        ])
    }

    private func extractRoomId(from raw: String) -> String? {
        let pattern = "[A-Z][0-9][A-Z][0-9][A-Z][0-9]"
        let upper = raw.uppercased()
        guard let range = upper.range(of: pattern, options: .regularExpression) else { return nil }
        return String(upper[range])
    }

    private func saveSession(roomId: String, roomKey: String, userName: String, isHost: Bool) {
        let session = SavedRoomSession(roomId: roomId, roomKey: roomKey, userName: userName, isHost: isHost, timestamp: nowMs())
        if let data = try? JSONEncoder().encode(session) {
            prefs.set(data, forKey: "saved_room_session")
        }
    }

    public func checkPendingRejoinSession() {
        guard let data = prefs.data(forKey: "saved_room_session"),
              let session = try? JSONDecoder().decode(SavedRoomSession.self, from: data) else { return }
        let ageMs = nowMs() - session.timestamp
        if ageMs < 12 * 3600 * 1000 {
            pendingRejoinSession = session
        } else {
            prefs.removeObject(forKey: "saved_room_session")
        }
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
