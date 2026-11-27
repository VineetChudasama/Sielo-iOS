import Foundation
import SieloCoreModels

public enum RoomConnectionState: String, Sendable {
    case disconnected = "DISCONNECTED"
    case connecting = "CONNECTING"
    case connected = "CONNECTED"
    case reconnecting = "RECONNECTING"
    case error = "ERROR"
}

public struct RoomParticipant: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var isHost: Bool
    public let joinedAt: Int64
    public var songsAddedCount: Int = 0
}

public struct RoomChatMessage: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let senderId: String
    public let senderName: String
    public let text: String
    public let timestamp: Int64
    public let isHost: Bool
    public let isSystemEvent: Bool
    public var replyToText: String?
    public var replyToSender: String?
}

public struct RoomQueueItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let track: SieloTrack
    public let addedBy: String
    public let addedAt: Int64
}

public struct ActiveRoomState: Sendable {
    public let roomId: String
    public let roomKey: String
    public let localUserId: String
    public let localUserName: String
    public var isHost: Bool
    public var participants: [RoomParticipant]
    public var queue: [RoomQueueItem]
    public var currentTrack: SieloTrack?
    public var isPlaying: Bool
    public var positionMs: Int64
    public var messages: [RoomChatMessage]
    public var typingUsers: [String: String]
    public var connectionState: RoomConnectionState

    public var inviteURL: String {
        "https://sielo.site/listen/\(roomId)?key=\(roomKey)"
    }
}

public struct SavedRoomSession: Codable, Sendable {
    public let roomId: String
    public let roomKey: String
    public let userName: String
    public let isHost: Bool
    public let timestamp: Int64
}

public struct RoomEvent: Codable, Sendable {
    public let type: String
    public var senderId: String = ""
    public var senderName: String = ""
    public var timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    public var sequenceNumber: Int64 = 0
    public var action: String?
    public var positionMs: Int64?
    public var isPlaying: Bool?
    public var track: SieloTrack?
    public var queue: [RoomQueueItem]?
    public var message: RoomChatMessage?
    public var isTyping: Bool?
    public var targetUserId: String?
    public var scheduledStartMs: Int64?
    public var participants: [RoomParticipant]?
}
