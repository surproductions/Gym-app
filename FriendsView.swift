import Charts
import SwiftUI

/// The Friends part of the People tab.
struct FriendsSection: View {
    let person: Person
    @State private var store: FriendsStore
    @State private var showJoin = false
    @State private var showAdd = false
    @State private var code = ""
    @State private var addResult: String?

    init(person: Person) {
        self.person = person
        _store = State(initialValue: FriendsStore(personID: person.id))
    }

    private var incoming: [FriendRow] { store.friends.filter { !$0.accepted && $0.incoming } }
    private var outgoing: [FriendRow] { store.friends.filter { !$0.accepted && !$0.incoming } }
    private var accepted: [FriendRow] { store.friends.filter(\.accepted) }

    var body: some View {
        Section {
            if let me = store.me {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your friend code").font(.caption).foregroundStyle(.secondary)
                        Text(me.invite_code).font(.title2.bold().monospaced())
                    }
                    Spacer()
                    ShareLink(item: "Add me on Gym Log! My friend code is \(me.invite_code)") {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }

                ForEach(incoming) { f in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(f.name).font(.headline)
                            Text("wants to be friends").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Accept") { Task { await store.respond(f, accept: true) } }
                            .buttonStyle(.borderedProminent)
                        Button("No") { Task { await store.respond(f, accept: false) } }
                            .buttonStyle(.bordered)
                    }
                }

                ForEach(accepted) { f in
                    NavigationLink {
                        FriendDetailView(friend: f, store: store)
                    } label: {
                        FriendRowView(friend: f)
                    }
                }

                ForEach(outgoing) { f in
                    Label("Waiting for \(f.name) to accept", systemImage: "hourglass")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                Button {
                    code = ""
                    showAdd = true
                } label: {
                    Label("Add a friend", systemImage: "person.badge.plus")
                }

                if !store.cheers.isEmpty {
                    DisclosureGroup("Cheers you got (\(store.cheers.count))") {
                        ForEach(Array(store.cheers.reversed().prefix(10))) { c in
                            HStack(alignment: .top) {
                                Text(c.emoji)
                                VStack(alignment: .leading) {
                                    Text(c.from).font(.subheadline.bold())
                                    if let m = c.message, !m.isEmpty { Text(m).font(.subheadline) }
                                    Text(c.at, style: .relative).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                NavigationLink {
                    FriendPrivacyView(store: store)
                } label: {
                    Label("What friends can see", systemImage: "eye")
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("See your friends' workouts, PRs, weight and food, and let them see yours. You pick what to share.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        showJoin = true
                    } label: {
                        Label("Start sharing with friends", systemImage: "person.2.wave.2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }

            if store.loading { ProgressView() }
            if let e = store.error { Text(e).font(.caption).foregroundStyle(.red) }
        } header: {
            Text("Friends")
        } footer: {
            if store.me != nil {
                Text("Friends see what you share, updated whenever you open Gym Log. Cheers show up as notifications next time the app is opened.")
            }
        }
        .task { await store.refresh() }
        .sheet(isPresented: $showJoin) {
            JoinFriendsSheet(defaultName: person.name) { name, w, b, f in
                Task { await store.join(name: name, workouts: w, body: b, food: f); await store.refresh() }
            }
        }
        .alert("Add a friend", isPresented: $showAdd) {
            TextField("Friend code", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Add") {
                Task { addResult = await store.add(code: code) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ask your friend for the 6-letter code on their People tab.")
        }
        .alert(addResult ?? "", isPresented: Binding(get: { addResult != nil }, set: { if !$0 { addResult = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}

struct FriendRowView: View {
    let friend: FriendRow

    var body: some View {
        let s = friend.snapshot
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.2))
                Text(String(friend.name.prefix(1)).uppercased()).font(.headline)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name).font(.headline)
                if let st = s?.streak {
                    Text("\(st.weekDone)/\(st.weekPlanned) this week" + (st.weeks > 0 ? " · 🔥 \(st.weeks)-week streak" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let today = s?.food?.last, Calendar.current.isDateInToday(today.date) {
                    Text("Today: \(Int(today.kcal)) kcal · \(Int(today.protein)) g protein")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let at = friend.snapshot_at {
                    Text("Updated \(at.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text("Hasn't synced yet").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct JoinFriendsSheet: View {
    let defaultName: String
    let onJoin: (String, Bool, Bool, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var workouts = true
    @State private var body_ = true
    @State private var food = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name friends will see", text: $name)
                } header: {
                    Text("Your name")
                }
                Section {
                    Toggle("Workouts, lifts and PRs", isOn: $workouts)
                    Toggle("Body weight and goal", isOn: $body_)
                    Toggle("Food and water", isOn: $food)
                } header: {
                    Text("What friends can see")
                } footer: {
                    Text("Only people you accept as friends can see this. You can change it or stop sharing anytime. Your data is stored on a Gym Log server.")
                }
            }
            .navigationTitle("Share with friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onJoin(name.trimmingCharacters(in: .whitespaces), workouts, body_, food)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = defaultName }
        }
    }
}

struct FriendPrivacyView: View {
    let store: FriendsStore
    @State private var workouts = true
    @State private var body_ = true
    @State private var food = true
    @State private var confirmLeave = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Toggle("Workouts, lifts and PRs", isOn: $workouts)
                Toggle("Body weight and goal", isOn: $body_)
                Toggle("Food and water", isOn: $food)
            } footer: {
                Text("Turning something off hides it from all your friends right away.")
            }
            Section {
                Button("Stop sharing and delete my friend data", role: .destructive) { confirmLeave = true }
            } footer: {
                Text("Removes you from everyone's friend list and deletes what you've shared from the server. Your workouts on this phone stay.")
            }
        }
        .navigationTitle("What friends can see")
        .onAppear {
            if let me = store.me {
                workouts = me.share_workouts
                body_ = me.share_body
                food = me.share_food
            }
        }
        .onChange(of: [workouts, body_, food]) { _, v in
            guard let me = store.me, v != [me.share_workouts, me.share_body, me.share_food] else { return }
            Task { await store.updateShares(workouts: v[0], body: v[1], food: v[2]) }
        }
        .confirmationDialog("Stop sharing?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Stop sharing", role: .destructive) {
                Task {
                    await store.leave()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - One friend

struct FriendDetailView: View {
    let friend: FriendRow
    let store: FriendsStore
    @State private var sent: String?
    @State private var liftIndex = 0
    @State private var confirmRemove = false
    @Environment(\.dismiss) private var dismiss

    private let cheers: [(String, String)] = [
        ("🔥", "Keep it up!"), ("💪", "Strong work!"), ("👏", "Proud of you"), ("🏋️", "Gym today?"),
    ]

    private var current: FriendRow { store.friends.first { $0.id == friend.id } ?? friend }

    var body: some View {
        let f = current
        let s = f.snapshot
        List {
            Section {
                HStack(spacing: 8) {
                    ForEach(cheers.indices, id: \.self) { i in
                        let c = cheers[i]
                        Button {
                            Task {
                                if await store.cheer(f, emoji: c.0, message: c.1) { sent = "Sent \(c.0) to \(f.name)" }
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(c.0).font(.title2)
                                Text(c.1).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if let sent { Text(sent).font(.caption).foregroundStyle(.green) }
            } header: {
                Text("Send a cheer")
            }

            if s == nil {
                Section { Text("\(f.name) hasn't synced yet. Their stats show up after they open Gym Log.").foregroundStyle(.secondary) }
            }

            if let st = s?.streak {
                Section("This week") {
                    HStack {
                        stat("\(st.weekDone)/\(st.weekPlanned)", "workouts")
                        Divider()
                        stat("\(st.weeks)", st.weeks == 1 ? "week streak" : "week streak")
                        if let w = s?.workouts?.last {
                            Divider()
                            stat(w.date.formatted(.dateTime.weekday(.abbreviated)), "last workout")
                        }
                    }
                }
            } else if s != nil && !f.share_workouts {
                Section { Label("\(f.name) isn't sharing workouts", systemImage: "eye.slash").foregroundStyle(.secondary) }
            }

            if let ws = s?.workouts, !ws.isEmpty {
                Section("Recent workouts") {
                    ForEach(ws.suffix(8).reversed()) { w in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(w.day).font(.subheadline.bold())
                                Text(w.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(w.done)/\(w.total) · \(w.minutes) min").font(.caption.monospacedDigit())
                                if let hr = w.avgHR { Text("♥︎ \(Int(hr)) bpm").font(.caption2).foregroundStyle(.red) }
                            }
                        }
                    }
                }
            }

            if let prs = s?.prs, !prs.isEmpty {
                Section("Best lifts") {
                    ForEach(prs.prefix(10)) { p in
                        HStack {
                            Text(p.exercise).font(.subheadline)
                            Spacer()
                            Text(p.timed ? "\(p.reps)s" : "\(formatWeight(p.weight)) lb\(p.assisted ? " assist" : "") × \(p.reps)")
                                .font(.subheadline.monospacedDigit().bold())
                        }
                    }
                }
            }

            if let lifts = s?.lifts, !lifts.isEmpty {
                Section("Lift progress") {
                    Picker("Lift", selection: $liftIndex) {
                        ForEach(lifts.indices, id: \.self) { Text(lifts[$0].exercise).tag($0) }
                    }
                    let l = lifts[min(liftIndex, lifts.count - 1)]
                    Chart(l.points, id: \.date) {
                        LineMark(x: .value("Date", $0.date), y: .value("lb", $0.value))
                        PointMark(x: .value("Date", $0.date), y: .value("lb", $0.value)).symbolSize(20)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 160)
                }
            }

            if let bw = s?.body, !bw.isEmpty {
                Section("Body weight") {
                    HStack {
                        stat("\(formatWeight(bw.last!.value)) lb", "now")
                        if let g = s?.goalWeight {
                            Divider()
                            stat("\(formatWeight(g)) lb", "goal")
                        }
                        if bw.count > 1 {
                            Divider()
                            let change = bw.last!.value - bw.first!.value
                            stat(String(format: "%+.1f", change), "since \(bw.first!.date.formatted(.dateTime.month(.abbreviated).day()))")
                        }
                    }
                    if bw.count > 1 {
                        Chart {
                            ForEach(bw, id: \.date) {
                                LineMark(x: .value("Date", $0.date), y: .value("lb", $0.value))
                            }
                            if let g = s?.goalWeight {
                                RuleMark(y: .value("Goal", g)).lineStyle(StrokeStyle(dash: [4, 4])).foregroundStyle(.green)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 160)
                    }
                }
            } else if s != nil && !f.share_body {
                Section { Label("\(f.name) isn't sharing body weight", systemImage: "eye.slash").foregroundStyle(.secondary) }
            }

            if let food = s?.food, !food.isEmpty {
                Section("Food (last 7 days)") {
                    ForEach(food.suffix(7).reversed(), id: \.date) { d in
                        HStack {
                            Text(Calendar.current.isDateInToday(d.date) ? "Today" : d.date.formatted(.dateTime.weekday(.abbreviated).day()))
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(d.kcal)) kcal · \(Int(d.protein)) g").font(.subheadline.monospacedDigit())
                                .foregroundStyle(hit(d) ? Color.green : Color.primary)
                        }
                    }
                    if let t = s?.targets {
                        Text("Targets: \(Int(t.kcal)) kcal · \(Int(t.protein)) g protein").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let water = s?.water, !water.isEmpty {
                Section("Water") {
                    ForEach(water.suffix(5).reversed(), id: \.date) { d in
                        HStack {
                            Text(Calendar.current.isDateInToday(d.date) ? "Today" : d.date.formatted(.dateTime.weekday(.abbreviated).day()))
                            Spacer()
                            Text("\(Int(d.oz)) oz" + (s?.waterGoal.map { " / \(Int($0))" } ?? "")).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            } else if s != nil && !f.share_food {
                Section { Label("\(f.name) isn't sharing food", systemImage: "eye.slash").foregroundStyle(.secondary) }
            }

            Section {
                Button("Remove friend", role: .destructive) { confirmRemove = true }
            }
        }
        .navigationTitle(f.name)
        .refreshable { await store.refresh() }
        .themedBackground()
        .confirmationDialog("Remove \(f.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    await store.remove(f)
                    dismiss()
                }
            }
        } message: {
            Text("You'll stop seeing each other's stats. You can add each other again with your codes.")
        }
    }

    private func hit(_ d: FriendSnapshot.DayFood) -> Bool {
        guard let t = current.snapshot?.targets else { return false }
        return d.kcal >= t.kcal * 0.95 && d.protein >= t.protein * 0.95
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
