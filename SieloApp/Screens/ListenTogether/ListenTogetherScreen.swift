import SwiftUI
import SieloCoreModels
import SieloCoreNetwork

/// Mirrors ListenTogetherScreen.kt:
/// Lobby (Create Room, Join via Code/Link, QR Modal) & ActiveRoom (PlayerCard, LiveChat, CollaborativeQueue).
public struct ListenTogetherScreen: View {
    @EnvironmentObject private var container: SieloContainer
    @ObservedObject var router: SieloRouter

    @State private var roomCodeInput: String = ""
    @State private var chatInput: String = ""
    @State private var selectedRoomTab: Int = 0 // 0 = Chat, 1 = Queue
    @State private var showQRModal: Bool = false
    @State private var showAddTrackSheet: Bool = false
    @State private var roomSearchQuery: String = ""
    @State private var roomSearchResults: [SieloTrack] = []

    public init(router: SieloRouter) {
        self.router = router
    }

    public var body: some View {
        let manager = container.listenTogetherManager
        Group {
            if let active = manager.roomState {
                activeRoomView(active, manager: manager)
                    .onAppear { router.isInsideRoomScreen = true }
                    .onDisappear { router.isInsideRoomScreen = false }
            } else {
                lobbyView(manager: manager)
                    .onAppear { router.isInsideRoomScreen = false }
            }
        }
        .background(SieloColors.obsidianBlack.ignoresSafeArea())
    }

    private func lobbyView(manager: ListenTogetherManager) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Echo • Listen Together")
                    .font(SieloTypography.headlineLarge)
                    .foregroundColor(SieloColors.cream)

                Text("End-to-end encrypted (AES-256-GCM) rooms with sub-150ms drift compensation across Android & iOS.")
                    .font(SieloTypography.bodyMedium)
                    .foregroundColor(SieloColors.textSecondary)

                Button {
                    let name = container.userManager.currentUser?.name ?? "Host"
                    manager.createRoom(userName: name)
                } label: {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        Text("Create Encrypted Room")
                            .font(SieloTypography.titleSmall)
                    }
                    .foregroundColor(SieloColors.obsidianBlack)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SieloColors.sand)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Join via Room Code or Invite Link")
                        .font(SieloTypography.titleSmall)
                        .foregroundColor(SieloColors.cream)
                    HStack {
                        TextField("e.g. A1B2C3 or sielo.site/listen/...", text: $roomCodeInput)
                            .foregroundColor(SieloColors.cream)
                            .padding(12)
                            .background(SieloColors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button("Join") {
                            let name = container.userManager.currentUser?.name ?? "Listener"
                            _ = manager.joinRoom(rawInput: roomCodeInput, userName: name)
                        }
                        .font(SieloTypography.titleSmall)
                        .foregroundColor(SieloColors.obsidianBlack)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(SieloColors.sand)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)
                .background(SieloColors.oxfordBlue)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .padding(16)
            .padding(.bottom, 140)
        }
    }

    private func activeRoomView(_ room: ActiveRoomState, manager: ListenTogetherManager) -> some View {
        VStack(spacing: 12) {
            // Top Bar
            HStack {
                Button {
                    manager.leaveRoom(intentional: true)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(SieloColors.cream)
                        .padding(8)
                        .background(SieloColors.oxfordBlue)
                        .clipShape(Circle())
                }

                VStack(alignment: .leading) {
                    Text("Room \(room.roomId)")
                        .font(SieloTypography.titleMedium)
                        .foregroundColor(SieloColors.cream)
                    Text("\(room.participants.count) listening • \(room.connectionState.rawValue)")
                        .font(SieloTypography.labelSmall)
                        .foregroundColor(SieloColors.sageGreen)
                }

                Spacer()

                Button { showQRModal = true } label: {
                    Image(systemName: "qrcode")
                        .foregroundColor(SieloColors.sand)
                        .padding(8)
                        .background(SieloColors.oxfordBlue)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Room Player Card
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.currentTrack?.title ?? "No track playing")
                        .font(SieloTypography.titleSmall)
                        .foregroundColor(SieloColors.cream)
                        .lineLimit(1)
                    Text(room.currentTrack?.artist ?? "Add a song to the room queue")
                        .font(SieloTypography.bodySmall)
                        .foregroundColor(SieloColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button { manager.togglePlayPause() } label: {
                    Image(systemName: room.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(SieloColors.sand)
                }
            }
            .padding(14)
            .background(SieloColors.oxfordBlue)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)

            Picker("Room View", selection: $selectedRoomTab) {
                Text("Live Chat").tag(0)
                Text("Queue (\(room.queue.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            if selectedRoomTab == 0 {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(room.messages) { msg in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(msg.senderName)
                                    .font(SieloTypography.labelSmall)
                                    .foregroundColor(SieloColors.sand)
                                Text(msg.text)
                                    .font(SieloTypography.bodyMedium)
                                    .foregroundColor(SieloColors.cream)
                            }
                            .padding(10)
                            .background(SieloColors.oxfordBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 16)
                }

                HStack {
                    TextField("Message room...", text: $chatInput)
                        .foregroundColor(SieloColors.cream)
                        .padding(10)
                        .background(SieloColors.oxfordBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Button("Send") {
                        manager.sendChatMessage(chatInput)
                        chatInput = ""
                    }
                    .foregroundColor(SieloColors.sand)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            } else {
                VStack {
                    Button("+ Add Track to Room") {
                        showAddTrackSheet = true
                    }
                    .font(SieloTypography.titleSmall)
                    .foregroundColor(SieloColors.sand)
                    .padding(.vertical, 6)

                    List(room.queue) { item in
                        VStack(alignment: .leading) {
                            Text(item.track.title).foregroundColor(SieloColors.cream)
                            Text("Added by \(item.addedBy)").font(.caption).foregroundColor(SieloColors.textSecondary)
                        }
                        .listRowBackground(SieloColors.oxfordBlue)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .sheet(isPresented: $showQRModal) {
            VStack(spacing: 16) {
                Text("Invite to Room \(room.roomId)")
                    .font(SieloTypography.headlineMedium)
                    .foregroundColor(SieloColors.cream)
                if let qr = ListenTogetherManager.generateQRCode(for: room.inviteURL) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 220, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                ShareLink(item: room.inviteURL) {
                    Label("Share Invite Link", systemImage: "square.and.arrow.up")
                        .foregroundColor(SieloColors.sand)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SieloColors.obsidianBlack)
        }
        .sheet(isPresented: $showAddTrackSheet) {
            NavigationStack {
                VStack {
                    TextField("Search song...", text: $roomSearchQuery)
                        .padding(10)
                        .background(SieloColors.oxfordBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                        .onSubmit {
                            Task {
                                roomSearchResults = await InnerTubeClient.shared.search(query: roomSearchQuery).tracks
                            }
                        }
                    List(roomSearchResults) { track in
                        Button {
                            manager.addToQueue(track)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(track.title).foregroundColor(SieloColors.cream)
                                    Text(track.artist).font(.caption).foregroundColor(SieloColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundColor(SieloColors.sand)
                            }
                        }
                        .listRowBackground(SieloColors.oxfordBlue)
                    }
                    .scrollContentBackground(.hidden)
                }
                .background(SieloColors.obsidianBlack)
                .navigationTitle("Add to Room")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showAddTrackSheet = false }
                    }
                }
            }
        }
    }
}
