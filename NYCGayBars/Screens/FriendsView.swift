import SwiftUI
import UserNotifications

/// Friends tab: onboarding, invite code, requests, friends list, and the
/// Tonight feed of friends' shared check-ins. All state lives in SocialStore
/// (CloudKit public DB); nothing here touches drink history.
struct FriendsView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var tabSwipe: TabSwipe

    private enum Field { case name, code }

    @State private var nameDraft = ""
    @State private var codeDraft = ""
    @FocusState private var focusedField: Field?
    @State private var selectedBar: Bar?
    @State private var removeTarget: FriendProfile?
    @State private var showRemoveConfirm = false
    @State private var showQR = false
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
                        .focused($focusedField, equals: .name)
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
        .scrollDismissesKeyboard(.interactively)
        // Tap anywhere outside the text field to drop the keyboard; buttons
        // and the field itself win the gesture, so they're unaffected.
        .onTapGesture { focusedField = nil }
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
                if let info = social.infoMessage {
                    infoBanner(info).padding(.bottom, 12)
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
        .scrollDismissesKeyboard(.interactively)
        // Tap anywhere outside the text field to drop the keyboard; buttons
        // and the field itself win the gesture, so they're unaffected.
        .onTapGesture { focusedField = nil }
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

    private func infoBanner(_ message: String) -> some View {
        Text(message)
            .font(.scaled(14)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.green.opacity(0.2)))
            .onTapGesture { social.infoMessage = nil }
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
            Button {
                Haptics.light()
                showQR = true
            } label: {
                Image(systemName: "qrcode")
                    .font(.scaled(18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassSurface(radius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show QR code")
            .padding(.trailing, 8)
            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.scaled(18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassSurface(radius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share friend link")
        }
        .padding(16)
        .contentPanel()
        .sheet(isPresented: $showQR) { qrSheet }
    }

    /// Texted share: the https page link is tappable in Messages and bounces
    /// into the app via nycgaybars://.
    private var shareText: String {
        let code = social.profile?.code ?? ""
        return "Add me on NYC Gay Bars — my friend code is \(code). \(Social.addFriendLink(code: code).absoluteString)"
    }

    private var qrSheet: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 14) {
                Text(social.profile?.displayName ?? "")
                    .font(.scaled(20, weight: .heavy)).foregroundStyle(.white)
                Text("Scan with the iPhone Camera to add me")
                    .font(.scaled(13)).foregroundStyle(Palette.gray400)
                if let code = social.profile?.code,
                   let qr = qrCodeImage(for: Social.addFriendDeepLink(code: code).absoluteString) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white))
                }
                Text(social.profile?.code ?? "")
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Palette.primary)
                ShareLink(item: shareText) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.scaled(15, weight: .semibold))
                        Text("Share link").font(.scaled(16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .glassSurface(radius: 22, bordered: true)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: Add friend

    private var addFriendRow: some View {
        HStack(spacing: 8) {
            TextField("", text: $codeDraft,
                      prompt: Text("Friend code…").foregroundStyle(Palette.gray400))
                .focused($focusedField, equals: .code)
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
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(social.friends) { friendRow($0) }
                    Text("Paper plane: they get your check-ins. Bell: their check-ins notify you.")
                        .font(.scaled(12)).foregroundStyle(Palette.gray500)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func friendRow(_ friend: FriendProfile) -> some View {
        HStack(spacing: 0) {
            Text(friend.displayName)
                .font(.scaled(15, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            prefToggle(on: social.prefs.sendsTo(friend.id),
                       onIcon: "paperplane.fill", offIcon: "paperplane",
                       label: "Send your check-ins to \(friend.displayName): \(social.prefs.sendsTo(friend.id) ? "on" : "off")") {
                social.toggleSend(friend)
            }
            prefToggle(on: social.prefs.getsFrom(friend.id),
                       onIcon: "bell.fill", offIcon: "bell.slash",
                       label: "Get notified about \(friend.displayName): \(social.prefs.getsFrom(friend.id) ? "on" : "off")") {
                Task { await social.toggleGet(friend) }
            }
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

    private func prefToggle(on: Bool, onIcon: String, offIcon: String,
                            label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: on ? onIcon : offIcon)
                .font(.scaled(14, weight: .semibold))
                .foregroundStyle(on ? Palette.primary : Palette.gray500)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Helpers

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }
}
