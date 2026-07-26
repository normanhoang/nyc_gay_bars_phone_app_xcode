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
    // Own check-in pending removal (confirmation dialog).
    @State private var removeCheckInTarget: FriendCheckIn?

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
        // Poll while the Friends tab is open so accepted/removed friendships
        // become mutual within seconds even if the CloudKit silent push was
        // dropped. Auto-cancels when the active page changes; keyed on
        // onboarded too so finishing onboarding on-tab starts the poll.
        .task(id: "\(tabSwipe.page)-\(social.onboarded)") {
            guard tabSwipe.page == .friends, social.onboarded else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if Task.isCancelled { break }
                await social.refresh()
            }
        }
        .onChange(of: tabSwipe.page) { _, p in
            // Reset scroll once this page goes offscreen so the next visit
            // always starts at the top; refresh when swiped back in.
            if p != .friends {
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
                Text("Friends").font(.scaled(22, weight: .heavy)).foregroundStyle(.white)
                    .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text("See when your friends are out")
                        .font(.scaled(18, weight: .bold)).foregroundStyle(.white)

                    valueProp("qrcode", "Private code, no accounts",
                              "Add friends with a code or QR — there's no directory to be found in.")
                    valueProp("wineglass", "Share only when you tap",
                              "Logging drinks never notifies anyone — “Share with friends” is its own button.")
                    valueProp("clock.arrow.circlepath", "Check-ins expire",
                              "Friends see them for 3 hours; they're deleted after 6.")

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
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(focusedField == .name ? Palette.primary.opacity(0.6) : Color.white.opacity(0.10), lineWidth: 1))

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
                            .shadow(color: startDisabled ? .clear : Palette.primary.opacity(0.45), radius: 10, y: 2)
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

    /// Icon-tile value-prop row for onboarding (redesign 6c).
    private func valueProp(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.scaled(16, weight: .semibold))
                .foregroundStyle(Palette.primary)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.primary.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.primary.opacity(0.3), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.scaled(14, weight: .semibold)).foregroundStyle(.white)
                Text(body).font(.scaled(13)).foregroundStyle(Palette.gray400)
            }
        }
        .padding(.top, 4)
    }

    private var startDisabled: Bool {
        social.busy || nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Main content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Friends").font(.scaled(22, weight: .heavy)).foregroundStyle(.white)
                    Spacer()
                    Button {
                        Haptics.light()
                        sheetDetent = .medium
                        editingName = false
                        showAddSheet = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.scaled(16, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .glassSurface(radius: 12, bordered: true)
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

                if !social.incomingRequests.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(social.incomingRequests) { requestBanner($0) }
                    }
                    .padding(.bottom, 20)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Tonight").font(.scaled(16, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    let out = social.friendsTonight
                    if !out.isEmpty {
                        let n = Set(out.map(\.authorID)).count
                        Text("\(n) friend\(n == 1 ? "" : "s") out")
                            .font(.scaled(12)).foregroundStyle(Palette.gray400)
                    }
                }
                .padding(.bottom, 8)
                tonightSection.padding(.bottom, 20)

                if !social.friends.isEmpty {
                    Text("Groups").font(.scaled(16, weight: .bold)).foregroundStyle(.white)
                        .padding(.bottom, 8)
                    groupsSection.padding(.bottom, 20)
                }

                Text("Your friends").font(.scaled(16, weight: .bold)).foregroundStyle(.white)
                    .padding(.bottom, 8)
                friendsSection

                Text("Check-ins share only your display name and the bar. Friends see them for 3 hours; they're deleted after 6. Remove yours anytime from Tonight.")
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
        // `presenting:` hands the check-in to the builder, so the action can't
        // read a target the dismissal has already nil'd out.
        .confirmationDialog("Remove your check-in?",
                            isPresented: Binding(get: { removeCheckInTarget != nil },
                                                 set: { if !$0 { removeCheckInTarget = nil } }),
                            titleVisibility: .visible,
                            presenting: removeCheckInTarget) { checkIn in
            Button("Remove", role: .destructive) {
                Haptics.light()
                Task { await social.removeOwnCheckIn(checkIn) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { checkIn in
            Text("Friends will stop seeing you at \(checkIn.barName).")
        }
    }

    // MARK: Groups

    /// Groups as chips: tap opens the group sheet (members, sharing toggle,
    /// rename and delete).
    private var groupsSection: some View {
        FlowLayout(spacing: 8) {
            ForEach(social.prefs.groups) { groupChip($0) }
            Button {
                groupNameDraft = ""
                showNewGroup = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.scaled(12, weight: .semibold))
                    Text("New").font(.scaled(13, weight: .semibold))
                }
                .foregroundStyle(Palette.primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(Capsule().strokeBorder(Palette.primary.opacity(0.5),
                                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(PressableScale())
            .accessibilityLabel("New group")
        }
    }

    private func groupChip(_ group: FriendGroup) -> some View {
        Button {
            editMembersGroup = group
        } label: {
            HStack(spacing: 6) {
                Text(group.name).font(.scaled(13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text("\(group.members.count)")
                    .font(.scaled(11, weight: .semibold)).foregroundStyle(Palette.gray400)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(PressableScale())
        .accessibilityLabel("Open group \(group.name)")
    }

    private func membersSheet(_ group: FriendGroup) -> some View {
        // Re-read the live group so checkmarks reflect taps immediately.
        let live = social.prefs.groups.first { $0.id == group.id } ?? group
        let sends = social.prefs.groupSends(live)
        let gets = social.prefs.groupGets(live)
        return ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(live.name).font(.scaled(22, weight: .heavy)).foregroundStyle(.white)
                        Button {
                            groupNameDraft = live.name
                            renameGroupTarget = live
                        } label: {
                            Image(systemName: "pencil")
                                .font(.scaled(16, weight: .semibold)).foregroundStyle(Palette.gray300)
                        }
                        .buttonStyle(PressableScale())
                        .accessibilityLabel("Rename group")
                    }
                    Toggle(isOn: Binding(get: { sends },
                                         set: { social.setGroupSend(live, on: $0) })) {
                        HStack(spacing: 8) {
                            Image(systemName: sends ? "paperplane.fill" : "paperplane")
                                .font(.scaled(15)).foregroundStyle(sends ? Palette.primary : Palette.gray400)
                            Text("Share check-ins").font(.scaled(15, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                    .tint(Palette.primary)
                    .disabled(live.members.isEmpty)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .contentPanel(radius: 16)
                    if Social.checkInPushEnabled {
                        Toggle(isOn: Binding(get: { gets },
                                             set: { on in Task { await social.setGroupGet(live, on: on) } })) {
                            HStack(spacing: 8) {
                                Image(systemName: gets ? "bell.fill" : "bell.slash")
                                    .font(.scaled(15)).foregroundStyle(gets ? Palette.primary : Palette.gray400)
                                Text("Notify me").font(.scaled(15, weight: .semibold)).foregroundStyle(.white)
                            }
                        }
                        .tint(Palette.primary)
                        .disabled(live.members.isEmpty)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .contentPanel(radius: 16)
                    }
                    Text("Tap friends to add or remove them from this group.")
                        .font(.scaled(13)).foregroundStyle(Palette.gray400).padding(.vertical, 4)
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
                    Button {
                        deleteGroupTarget = live
                    } label: {
                        Text("Delete Group").font(.scaled(15, weight: .semibold))
                            .foregroundStyle(Palette.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentPanel(radius: 16)
                    }
                    .buttonStyle(PressableScale())
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                editMembersGroup = nil
            }
            Button("Cancel", role: .cancel) { deleteGroupTarget = nil }
        } message: {
            Text("This only deletes the group, not the friends in it.")
        }
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
                // Periodic timeline so ages and the "Now" dot keep ticking
                // while the page is visible.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 8) {
                        ForEach(social.tonight) { tonightCard($0, now: context.date) }
                    }
                }
            }
        }
    }

    /// Rich Tonight card: avatar, live dot, bar · neighborhood · age, Map chip
    /// that frames the bar on the Explore map (redesign 4a). My own check-in
    /// is badged "YOU" and swaps the Map chip for Remove — three trailing
    /// elements would squeeze the name out on a narrow phone.
    private func tonightCard(_ checkIn: FriendCheckIn, now: Date) -> some View {
        let minutes = max(0, Int(now.timeIntervalSince(checkIn.date) / 60))
        let age = minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h"
        let neighborhood = AppData.barsById[checkIn.barId]?.neighborhood
        let isMe = checkIn.authorID == social.myID
        return Button {
            if let bar = AppData.barsById[checkIn.barId] { selectedBar = bar }
        } label: {
            HStack(spacing: 12) {
                avatar(checkIn.authorName, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(checkIn.authorName)
                            .font(.scaled(15, weight: .bold)).foregroundStyle(.white)
                            .lineLimit(1)
                        if isMe { youBadge }
                        if minutes < 15 {
                            Circle().fill(Palette.green).frame(width: 6, height: 6)
                            Text("Now").font(.scaled(11, weight: .semibold)).foregroundStyle(Palette.green)
                        }
                    }
                    (Text(checkIn.barName).foregroundStyle(Palette.gray300)
                        + Text(neighborhood.map { " · \($0)" } ?? "").foregroundStyle(Palette.primary)
                        + Text(" · \(age)").foregroundStyle(Palette.gray400))
                        .font(.scaled(13))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isMe {
                    Button {
                        Haptics.light()
                        removeCheckInTarget = checkIn
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash").font(.scaled(12))
                            Text("Remove").font(.scaled(13, weight: .semibold))
                        }
                        .foregroundStyle(Palette.red)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(PressableScale())
                    .accessibilityLabel("Remove your check-in at \(checkIn.barName)")
                } else {
                    Button {
                        Haptics.light()
                        tabSwipe.mapTarget = checkIn.barId
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill").font(.scaled(12))
                            Text("Map").font(.scaled(13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(PressableScale())
                    .accessibilityLabel("Show \(checkIn.barName) on the map")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassSurface(radius: 16, bordered: true)
        }
        .buttonStyle(PressableScale())
    }

    private var youBadge: some View {
        Text("YOU")
            .font(.scaled(9, weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(Palette.primary))
    }

    /// Gradient initial avatar (redesign 4a).
    private func avatar(_ name: String, size: CGFloat) -> some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.scaled(size * 0.4, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(
                colors: [Palette.primary, Palette.violet],
                startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

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

    /// Primary-tinted request banner at the top of the screen (redesign 4a).
    private func requestBanner(_ request: FriendRequestItem) -> some View {
        HStack(spacing: 10) {
            (Text(request.fromName).fontWeight(.bold)
                + Text(" wants to be friends"))
                .font(.scaled(14)).foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                Haptics.success()
                Task { await social.accept(request) }
            } label: {
                Text("Accept").font(.scaled(14, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Palette.primary))
            }
            .buttonStyle(PressableScale())
            Button {
                social.ignore(request)
            } label: {
                Image(systemName: "xmark")
                    .font(.scaled(13, weight: .semibold)).foregroundStyle(Palette.gray300)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ignore request from \(request.fromName)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.primary.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.primary.opacity(0.3), lineWidth: 1))
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
                         ? "Sharing: they get your check-ins. Bell: their check-ins notify you."
                         : "Sharing: they see your check-ins in their Tonight feed.")
                        .font(.scaled(12)).foregroundStyle(Palette.gray500)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func friendRow(_ friend: FriendProfile) -> some View {
        let inGroups = social.prefs.groups.filter { $0.members.contains(friend.id) }
        let sharing = social.prefs.sendsTo(friend.id)
        return HStack(spacing: 10) {
            Button {
                groupsForFriend = friend
            } label: {
                HStack(spacing: 10) {
                    avatar(friend.displayName, size: 34)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(friend.displayName), show groups")

            // Labeled sharing chip in place of the paperplane icon toggle.
            Button {
                Haptics.light()
                social.toggleSend(friend)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: sharing ? "paperplane.fill" : "paperplane")
                        .font(.scaled(11, weight: .semibold))
                    Text(sharing ? "Sharing" : "Not sharing")
                        .font(.scaled(12, weight: .semibold))
                }
                .foregroundStyle(sharing ? Palette.primary : Palette.gray400)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(sharing ? Palette.primary.opacity(0.15) : Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(
                    sharing ? Palette.primary.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(PressableScale())
            .accessibilityLabel("Send your check-ins to \(friend.displayName): \(sharing ? "on" : "off")")

            // Bell controls check-in push subscriptions — hidden while check-in
            // pushes are disabled (Social.checkInPushEnabled) since it's inert.
            if Social.checkInPushEnabled {
                prefToggle(on: social.prefs.getsFrom(friend.id),
                           onIcon: "bell.fill", offIcon: "bell.slash",
                           label: "Get notified about \(friend.displayName): \(social.prefs.getsFrom(friend.id) ? "on" : "off")") {
                    Task { await social.toggleGet(friend) }
                }
            }

            Menu {
                Button(role: .destructive) {
                    removeTarget = friend
                    showRemoveConfirm = true
                } label: {
                    Label("Remove friend", systemImage: "person.fill.xmark")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.scaled(13, weight: .semibold)).foregroundStyle(Palette.gray400)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(friend.displayName) options")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
