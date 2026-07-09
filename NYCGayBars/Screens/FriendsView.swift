import SwiftUI
import UserNotifications

/// Friends tab: onboarding, invite code, requests, friends list, and the
/// Tonight feed of friends' shared check-ins. All state lives in SocialStore
/// (CloudKit public DB); nothing here touches drink history.
struct FriendsView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var tabSwipe: TabSwipe

    @State private var nameDraft = ""
    @State private var codeDraft = ""
    @State private var selectedBar: Bar?
    @State private var removeTarget: FriendProfile?
    @State private var showRemoveConfirm = false
    @State private var scrollPos = ScrollPosition()

    var body: some View {
        Group {
            if social.accountState == .unavailable {
                iCloudNotice
            } else if !social.onboarded {
                onboarding
            } else {
                content
            }
        }
        .sheet(item: $selectedBar) { bar in
            BarDetailSheet(bar: bar, day: nil)
        }
        .task { await social.start() }
        .onChange(of: tabSwipe.page) { _, p in
            // Reset scroll once this page goes offscreen so the next visit
            // always starts at the top; refresh when swiped back in.
            if p != 3 {
                scrollPos.scrollTo(edge: .top)
            } else if social.onboarded {
                Task { await social.refresh() }
            }
        }
        .confirmationDialog("Remove \(removeTarget?.displayName ?? "friend")?",
                            isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let friend = removeTarget {
                    Haptics.warning()
                    Task { await social.removeFriend(friend) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop getting their check-ins. They may still get yours until they remove you.")
        }
    }

    // MARK: - No iCloud

    private var iCloudNotice: some View {
        VStack(spacing: 12) {
            Text("👯").font(.scaled(36))
            Text("Sign in to iCloud in Settings to add friends and share check-ins.")
                .font(.scaled(16)).foregroundStyle(Palette.gray400)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Onboarding

    private var onboarding: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Friends").font(.scaled(30, weight: .heavy)).foregroundStyle(.white)
                    .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text("See when your friends are out")
                        .font(.scaled(18, weight: .bold)).foregroundStyle(.white)
                    Text("Add friends with a private code — no accounts, no directory. When you tap “Share with friends” at a bar, they get a ping like “Sam is at The Eagle”. Nothing is shared unless you tap it, and check-ins disappear after a few hours.")
                        .font(.scaled(14)).foregroundStyle(Palette.gray300)

                    Text("PICK A DISPLAY NAME").font(.scaled(12)).tracking(0.5)
                        .foregroundStyle(Palette.gray300).padding(.top, 8)
                    TextField("", text: $nameDraft,
                              prompt: Text("What friends will see…").foregroundStyle(Palette.gray400))
                        .foregroundStyle(.white)
                        .font(.scaled(16))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))

                    Button {
                        let name = nameDraft
                        Task {
                            await social.createProfile(displayName: name)
                            await requestNotificationPermission()
                        }
                    } label: {
                        Text(social.busy ? "Setting up…" : "Get started")
                            .font(.scaled(16, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Palette.primary.opacity(startDisabled ? 0.4 : 1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(startDisabled)

                    Text("A first name or nickname is plenty — it's the only thing friends ever see.")
                        .font(.scaled(12)).foregroundStyle(Palette.gray500)
                }
                .padding(16)
                .contentPanel()

                if let err = social.errorMessage {
                    errorBanner(err).padding(.top, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 104)
        }
    }

    private var startDisabled: Bool {
        social.busy || nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Main content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Friends").font(.scaled(30, weight: .heavy)).foregroundStyle(.white)
                    .padding(.bottom, 16)

                if let err = social.errorMessage {
                    errorBanner(err).padding(.bottom, 12)
                }

                sectionTitle("TONIGHT")
                tonightSection.padding(.bottom, 20)

                sectionTitle("MY CODE")
                myCodeCard.padding(.bottom, 20)

                sectionTitle("ADD A FRIEND")
                addFriendRow
                ForEach(social.outgoingRequests) { req in
                    Text("Waiting for your request to be accepted…")
                        .font(.scaled(12)).foregroundStyle(Palette.gray500)
                        .padding(.top, 6)
                        .id(req.id)
                }
                Color.clear.frame(height: 20)

                if !social.incomingRequests.isEmpty {
                    sectionTitle("REQUESTS")
                    VStack(spacing: 8) {
                        ForEach(social.incomingRequests) { requestRow($0) }
                    }
                    .padding(.bottom, 20)
                }

                sectionTitle("YOUR FRIENDS")
                friendsSection

                Text("Check-ins share only your display name and the bar. Friends see them for 6 hours; they're deleted after 24.")
                    .font(.scaled(12)).foregroundStyle(Palette.gray500)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 104)
        }
        .scrollPosition($scrollPos)
        .refreshable { await social.refresh() }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.scaled(12)).tracking(0.5)
            .foregroundStyle(Palette.gray300).padding(.bottom, 8)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.scaled(14)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.red.opacity(0.25)))
            .onTapGesture { social.errorMessage = nil }
    }

    // MARK: Tonight

    private var tonightSection: some View {
        Group {
            if social.tonight.isEmpty {
                Text(social.friends.isEmpty
                     ? "Add friends to see who's out tonight."
                     : "No friends out right now.")
                    .font(.scaled(14)).foregroundStyle(Palette.gray400)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .contentPanel()
            } else {
                VStack(spacing: 8) {
                    ForEach(social.tonight) { checkIn in
                        Button {
                            if let bar = AppData.barsById[checkIn.barId] { selectedBar = bar }
                        } label: {
                            HStack(spacing: 12) {
                                Text("🍸").font(.scaled(22))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(checkIn.authorName) is at \(checkIn.barName)")
                                        .font(.scaled(15, weight: .semibold)).foregroundStyle(.white)
                                        .multilineTextAlignment(.leading)
                                    Text(Self.relativeTime.localizedString(for: checkIn.date, relativeTo: Date()))
                                        .font(.scaled(12)).foregroundStyle(Palette.gray400)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.scaled(12, weight: .semibold)).foregroundStyle(Palette.gray500)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentPanel(radius: 16)
                        }
                        .buttonStyle(PressableScale())
                    }
                }
            }
        }
    }

    private static let relativeTime = RelativeDateTimeFormatter()

    // MARK: My code

    private var myCodeCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(social.profile?.code ?? "")
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Palette.primary)
                    .textSelection(.enabled)
                Text("Friends enter this code to add you.")
                    .font(.scaled(12)).foregroundStyle(Palette.gray400)
            }
            Spacer()
            ShareLink(item: "Add me on NYC Gay Bars — my friend code is \(social.profile?.code ?? "")") {
                Image(systemName: "square.and.arrow.up")
                    .font(.scaled(18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassSurface(radius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share friend code")
        }
        .padding(16)
        .contentPanel()
    }

    // MARK: Add friend

    private var addFriendRow: some View {
        HStack(spacing: 8) {
            TextField("", text: $codeDraft,
                      prompt: Text("Friend code…").foregroundStyle(Palette.gray400))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            Button {
                let code = codeDraft
                codeDraft = ""
                Task { await social.addFriend(code: code) }
            } label: {
                Text("Add")
                    .font(.scaled(16, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Palette.primary.opacity(addDisabled ? 0.4 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(addDisabled)
        }
    }

    private var addDisabled: Bool {
        social.busy || Social.normalizeCode(codeDraft) == nil
    }

    // MARK: Requests

    private func requestRow(_ request: FriendRequestItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.fromName).font(.scaled(15, weight: .semibold)).foregroundStyle(.white)
                Text("wants to be friends").font(.scaled(12)).foregroundStyle(Palette.gray400)
            }
            Spacer()
            Button {
                Haptics.success()
                Task { await social.accept(request) }
            } label: {
                Text("Accept").font(.scaled(14, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Palette.primary))
            }
            .buttonStyle(.plain)
            Button {
                social.ignore(request)
            } label: {
                Image(systemName: "xmark")
                    .font(.scaled(14, weight: .semibold)).foregroundStyle(Palette.gray400)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ignore request from \(request.fromName)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentPanel(radius: 16)
    }

    // MARK: Friends list

    private var friendsSection: some View {
        Group {
            if social.friends.isEmpty {
                Text("No friends yet — share your code to get started.")
                    .font(.scaled(14)).foregroundStyle(Palette.gray400)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .contentPanel()
            } else {
                VStack(spacing: 8) {
                    ForEach(social.friends) { friend in
                        HStack {
                            Text(friend.displayName)
                                .font(.scaled(15, weight: .semibold)).foregroundStyle(.white)
                            Spacer()
                            Button {
                                removeTarget = friend
                                showRemoveConfirm = true
                            } label: {
                                Image(systemName: "person.fill.xmark")
                                    .font(.scaled(14)).foregroundStyle(Palette.gray500)
                                    .frame(width: 36, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(friend.displayName)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentPanel(radius: 16)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }
}
