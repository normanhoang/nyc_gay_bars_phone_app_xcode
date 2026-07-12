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
    @State private var showAddSheet = false
    @State private var sheetDetent: PresentationDetent = .medium
    @State private var scrollPos = ScrollPosition()
    // Rename own name (in the code sheet).
    @State private var editingName = false
    @State private var renameDraft = ""
    // Friend groups.
    @State private var showNewGroup = false
    @State private var groupNameDraft = ""
    @State private var renameGroupTarget: FriendGroup?
    @State private var editMembersGroup: FriendGroup?
    @State private var groupsForFriend: FriendProfile?
    @State private var deleteGroupTarget: FriendGroup?

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
            Text("You'll stop getting their check-ins, and they'll stop getting yours.")
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
                    Text("Add friends with a private code — no accounts, no directory. When you tap “Share with friends” at a bar, it shows up in their Tonight feed — no notifications. Nothing is shared unless you tap it, and check-ins disappear after a few hours.")
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
                HStack {
                    Text("Friends").font(.scaled(30, weight: .heavy)).foregroundStyle(.white)
                    Spacer()
                    Button {
                        Haptics.light()
                        sheetDetent = .medium
                        editingName = false
                        showAddSheet = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.scaled(18, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glassSurface(radius: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("My code and add a friend")
                }
                .padding(.bottom, 16)

                if let err = social.errorMessage {
                    errorBanner(err).padding(.bottom, 12)
                }
                if let info = social.infoMessage {
                    infoBanner(info).padding(.bottom, 12)
                }

                sectionTitle("TONIGHT")
                tonightSection.padding(.bottom, 20)

                if !social.incomingRequests.isEmpty {
                    sectionTitle("REQUESTS")
                    VStack(spacing: 8) {
                        ForEach(social.incomingRequests) { requestRow($0) }
                    }
                    .padding(.bottom, 20)
                }

                if !social.friends.isEmpty {
                    HStack {
                        sectionTitle("GROUPS")
                        Spacer()
                        Button {
                            groupNameDraft = ""
                            showNewGroup = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.scaled(13, weight: .bold)).foregroundStyle(Palette.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New group")
                    }
                    groupsSection.padding(.bottom, 20)
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
        .sheet(isPresented: $showAddSheet) { addFriendSheet }
        .sheet(item: $editMembersGroup) { group in membersSheet(group) }
        .sheet(item: $groupsForFriend) { friend in friendGroupsSheet(friend) }
        .alert("New group", isPresented: $showNewGroup) {
            TextField("Group name", text: $groupNameDraft)
            Button("Create") { social.createGroup(name: groupNameDraft) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename group", isPresented: Binding(
            get: { renameGroupTarget != nil },
            set: { if !$0 { renameGroupTarget = nil } })) {
            TextField("Group name", text: $groupNameDraft)
            Button("Save") {
                if let g = renameGroupTarget { social.renameGroup(g, to: groupNameDraft) }
                renameGroupTarget = nil
            }
            Button("Cancel", role: .cancel) { renameGroupTarget = nil }
        }
        .confirmationDialog("Delete \(deleteGroupTarget?.name ?? "group")?",
                            isPresented: Binding(get: { deleteGroupTarget != nil },
                                                 set: { if !$0 { deleteGroupTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let g = deleteGroupTarget { social.deleteGroup(g) }
                deleteGroupTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteGroupTarget = nil }
        } message: {
            Text("This only deletes the group, not the friends in it.")
        }
    }

    // MARK: Groups

    private var groupsSection: some View {
        Group {
            if social.prefs.groups.isEmpty {
                Text("Create a group to toggle several friends' check-ins at once.")
                    .font(.scaled(14)).foregroundStyle(Palette.gray400)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .contentPanel()
            } else {
                VStack(spacing: 8) {
                    ForEach(social.prefs.groups) { groupRow($0) }
                }
            }
        }
    }

    private func groupRow(_ group: FriendGroup) -> some View {
        let sends = social.prefs.groupSends(group)
        let gets = social.prefs.groupGets(group)
        return HStack(spacing: 0) {
            Button {
                editMembersGroup = group
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.scaled(15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text("\(group.members.count) friend\(group.members.count == 1 ? "" : "s")")
                        .font(.scaled(12)).foregroundStyle(Palette.gray400)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit members of \(group.name)")
            Spacer(minLength: 8)
            prefToggle(on: sends, onIcon: "paperplane.fill", offIcon: "paperplane",
                       label: "Send your check-ins to everyone in \(group.name): \(sends ? "on" : "off")") {
                social.setGroupSend(group, on: !sends)
            }
            .disabled(group.members.isEmpty)
            if Social.checkInPushEnabled {
                prefToggle(on: gets, onIcon: "bell.fill", offIcon: "bell.slash",
                           label: "Get notified about everyone in \(group.name): \(gets ? "on" : "off")") {
                    Task { await social.setGroupGet(group, on: !gets) }
                }
                .disabled(group.members.isEmpty)
            }
            Menu {
                Button { groupNameDraft = group.name; renameGroupTarget = group } label: { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive) { deleteGroupTarget = group } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.scaled(14, weight: .semibold)).foregroundStyle(Palette.gray400)
                    .frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .accessibilityLabel("\(group.name) options")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentPanel(radius: 16)
    }

    private func membersSheet(_ group: FriendGroup) -> some View {
        // Re-read the live group so checkmarks reflect taps immediately.
        let live = social.prefs.groups.first { $0.id == group.id } ?? group
        return ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(live.name).font(.scaled(22, weight: .heavy)).foregroundStyle(.white)
                    Text("Tap friends to add or remove them from this group.")
                        .font(.scaled(13)).foregroundStyle(Palette.gray400).padding(.bottom, 4)
                    ForEach(social.friends) { friend in
                        let isMember = live.members.contains(friend.id)
                        Button {
                            Haptics.light()
                            social.setMembership(friend, in: live, member: !isMember)
                        } label: {
                            HStack {
                                Text(friend.displayName).font(.scaled(15, weight: .semibold)).foregroundStyle(.white)
                                Spacer()
                                Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                                    .font(.scaled(18)).foregroundStyle(isMember ? Palette.primary : Palette.gray500)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .contentPanel(radius: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // Groups a single friend belongs to; tap a row to add/remove.
    private func friendGroupsSheet(_ friend: FriendProfile) -> some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(friend.displayName).font(.scaled(22, weight: .heavy)).foregroundStyle(.white)
                    Text("Groups \(friend.displayName) is in. Tap to add or remove.")
                        .font(.scaled(13)).foregroundStyle(Palette.gray400).padding(.bottom, 4)
                    if social.prefs.groups.isEmpty {
                        Text("No groups yet. Create one from the Groups section.")
                            .font(.scaled(14)).foregroundStyle(Palette.gray400)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).contentPanel()
                    } else {
                        ForEach(social.prefs.groups) { group in
                            let isMember = group.members.contains(friend.id)
                            Button {
                                Haptics.light()
                                social.setMembership(friend, in: group, member: !isMember)
                            } label: {
                                HStack {
                                    Text(group.name).font(.scaled(15, weight: .semibold)).foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                                        .font(.scaled(18)).foregroundStyle(isMember ? Palette.primary : Palette.gray500)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .contentPanel(radius: 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                // Periodic timeline so "5 minutes ago" keeps ticking while
                // the page is visible.
                TimelineView(.periodic(from: .now, by: 60)) { context in
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
                                        Text(Self.relativeTime.localizedString(for: checkIn.date, relativeTo: context.date))
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
    }

    private static let relativeTime = RelativeDateTimeFormatter()

    // MARK: My code + add friend sheet

    /// Texted share: the https page link is tappable in Messages and bounces
    /// into the app via nycgaybars://.
    private var shareText: String {
        let code = social.profile?.code ?? ""
        return "Add me on NYC Gay Bars — my friend code is \(code). \(Social.addFriendLink(code: code).absoluteString)"
    }

    private var addFriendSheet: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 10) {
                    if editingName {
                        HStack(spacing: 8) {
                            TextField("", text: $renameDraft,
                                      prompt: Text("Your name").foregroundStyle(Palette.gray400))
                                .focused($focusedField, equals: .name)
                                .foregroundStyle(.white).font(.scaled(18, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                            Button {
                                let n = renameDraft
                                editingName = false
                                focusedField = nil
                                Task { await social.updateDisplayName(n) }
                            } label: {
                                Text("Save").font(.scaled(15, weight: .bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .background(Capsule().fill(Palette.primary.opacity(
                                        renameDraft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)))
                            }
                            .buttonStyle(.plain)
                            .disabled(renameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text(social.profile?.displayName ?? "")
                                .font(.scaled(20, weight: .heavy)).foregroundStyle(.white)
                            Button {
                                renameDraft = social.profile?.displayName ?? ""
                                editingName = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.scaled(15, weight: .semibold)).foregroundStyle(Palette.gray400)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit your name")
                        }
                    }
                    if let code = social.profile?.code,
                       let qr = qrCodeImage(for: Social.addFriendDeepLink(code: code).absoluteString) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
                    }
                    Text("Scan with the iPhone Camera to add me")
                        .font(.scaled(13)).foregroundStyle(Palette.gray400)
                    HStack(spacing: 12) {
                        Text(social.profile?.code ?? "")
                            .font(.system(size: 24, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Palette.primary)
                            .textSelection(.enabled)
                        ShareLink(item: shareText) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.scaled(16, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .glassSurface(radius: 20)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Share friend link")
                    }

                    sectionTitle("ADD A FRIEND")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    addFriendRow
                    ForEach(social.outgoingRequests) { req in
                        Text("Waiting for your request to be accepted…")
                            .font(.scaled(12)).foregroundStyle(Palette.gray500)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(req.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onTapGesture { focusedField = nil }
        // Jump to the large detent while a field is focused so it isn't hidden
        // behind the keyboard at the medium height.
        .onChange(of: focusedField) { _, f in
            if f != nil { sheetDetent = .large }
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
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
                    Text(Social.checkInPushEnabled
                         ? "Paper plane: they get your check-ins. Bell: their check-ins notify you."
                         : "Paper plane: they see your check-ins in their Tonight feed.")
                        .font(.scaled(12)).foregroundStyle(Palette.gray500)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func friendRow(_ friend: FriendProfile) -> some View {
        let inGroups = social.prefs.groups.filter { $0.members.contains(friend.id) }
        return HStack(spacing: 0) {
            Button {
                groupsForFriend = friend
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayName)
                        .font(.scaled(15, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1)
                    if !inGroups.isEmpty {
                        Text(inGroups.map(\.name).joined(separator: " · "))
                            .font(.scaled(11)).foregroundStyle(Palette.gray400)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(friend.displayName), show groups")
            Spacer(minLength: 8)
            prefToggle(on: social.prefs.sendsTo(friend.id),
                       onIcon: "paperplane.fill", offIcon: "paperplane",
                       label: "Send your check-ins to \(friend.displayName): \(social.prefs.sendsTo(friend.id) ? "on" : "off")") {
                social.toggleSend(friend)
            }
            // Bell controls check-in push subscriptions — hidden while check-in
            // pushes are disabled (Social.checkInPushEnabled) since it's inert.
            if Social.checkInPushEnabled {
                prefToggle(on: social.prefs.getsFrom(friend.id),
                           onIcon: "bell.fill", offIcon: "bell.slash",
                           label: "Get notified about \(friend.displayName): \(social.prefs.getsFrom(friend.id) ? "on" : "off")") {
                    Task { await social.toggleGet(friend) }
                }
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
