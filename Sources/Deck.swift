import SwiftUI
import UIKit

struct Deck: View {
  @EnvironmentObject var store: Store
  @DeckState var editEmpty = false
  let id: UUID
  var body: some View {
    if let i = store.data.sessions.firstIndex(where: { $0.id == id }) {
      if store.data.sessions[i].sets.isEmpty {
        VStack(spacing: 16) {
          Text("The programme is empty.").font(.title2.bold())
          Button("Edit programme") { editEmpty = true }.buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $editEmpty) { Editor(s: store.data.sessions[i]) }
      } else if store.data.sessions[i].meet {
        MeetProgramme(s: $store.data.sessions[i])
      } else {
        Timing(s: $store.data.sessions[i])
      }
    }
  }
}
struct MeetProgramme: View {
  @EnvironmentObject var store: Store
  @Binding var s: Session
  @DeckState var stopwatch = false
  @DeckState var editing = false
  @DeckState var report = false
  @DeckState var raceResult: Int?
  var body: some View {
    let efforts = s.efforts
    let done = s.completed
    let order = s.programmeIndices(for: efforts)
    List {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            "\(s.date.formatted(date:.abbreviated,time:.omitted)) · \(s.venue) · \(s.course) m pool"
          ).foregroundStyle(.secondary)
          Text("Race programme").font(.title2.bold())
          if order.count > 1 {
            Text("Touch and hold a race, then drag it up or down.").font(.footnote).foregroundStyle(.secondary)
          }
        }.listRowBackground(Color.clear).listRowSeparator(.hidden)
      }
      Section {
        ForEach(order, id: \.self) { i in
          let race = efforts[i].set
          let completed = done.contains(i)
          let running = s.started != nil && s.index == i
          let records = s.touches.filter { $0.effort == i }
          let ids = race.entrants ?? (s.index == i ? s.team : [])
          let swimmers =
            ids
            + Set(records.map(\.swimmer)).subtracting(ids).sorted { $0.uuidString < $1.uuidString }
          Button {
            if completed {
              raceResult = i
              report = true
            } else {
              var update = s
              if update.selectRace(i, roster: store.data.swimmers) {
                s = update
                stopwatch = true
              }
            }
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text("\(race.metres) m \(race.title)").font(.title3.bold())
                Spacer()
                Image(systemName: "chevron.right")
              }
              if !race.raceLabel.isEmpty { Text(race.raceLabel).font(.subheadline) }
              if swimmers.isEmpty { Text("No swimmers entered").foregroundStyle(.secondary) }
              ForEach(swimmers, id: \.self) { id in
                let finish =
                  swimSeconds(s.official[s.resultKey(id, i)])
                  ?? records.first { $0.swimmer == id && $0.mark == race.metres }?.seconds
                LabeledContent(
                  store.name(id),
                  value: completed
                    ? (s.outcome(id, i)?.title ?? finish.map(timeText) ?? "Untimed")
                    : (s.lanes[s.resultKey(id, i)].flatMap { $0.isEmpty ? nil : "Lane " + $0 } ?? "")
                )
              }
              Label(
                completed
                  ? "Completed · View results" : (running ? "Resume timing" : "Open stopwatch"),
                systemImage: completed ? "checkmark.circle.fill" : "stopwatch"
              ).font(.subheadline.bold()).foregroundStyle(completed ? Color.secondary : Color.meetAccent)
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(
              Color(uiColor: completed ? .systemGray5 : .secondarySystemGroupedBackground),
              in: RoundedRectangle(cornerRadius: 18))
          }.buttonStyle(.plain).disabled(!completed && s.started != nil && !running)
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        }.onMove { source, destination in
          var updated = order
          updated.move(fromOffsets: source, toOffset: destination)
          s.programmeOrder = updated.map { efforts[$0].programmeKey }
        }
      }
      Section {
        if !s.touches.isEmpty {
          Button("All meet results and exports") {
            raceResult = nil
            report = true
          }
        }
      }.listRowBackground(Color.clear).listRowSeparator(.hidden)
    }.listStyle(.plain)
    .sectionStyle(.meetAccent, strength: 0.23).navigationTitle(s.title)
    .toolbar { if s.started == nil { Button("Edit") { editing = true } } }
    .sheet(isPresented: $editing) { Editor(s: s) }
    .sheet(isPresented: $report) { NavigationStack { Results(s: $s, race: raceResult) } }
    .navigationDestination(isPresented: $stopwatch) { Timing(s: $s) }
  }
}
struct Timing: View {
  @Environment(\.dismiss) var dismiss
  @EnvironmentObject var store: Store
  @Binding var s: Session
  @AppStorage("ReverseLaneView") var reverse = false
  @DeckState var editing = false
  @DeckState var cancelRun = false
  @DeckState var selectedRace: Int?
  @DeckState var report = false
  @DeckState var manualID: UUID?
  @DeckState var manual = ""
  @Environment(\.scenePhase) var phase
  var effort: Effort { s.efforts[min(s.index, s.efforts.count - 1)] }
  var raceIndex: Int { s.sets.firstIndex { $0.id == effort.set.id } ?? 0 }
  var pendingTeam: [UUID] { s.meet ? (effort.set.entrants ?? s.team) : s.team }
  var canStart: Bool {
    !pendingTeam.isEmpty
      && (!s.meet
        || pendingTeam.allSatisfy { id in
          store.data.swimmers.first { $0.id == id }.map { effort.set.entryIssue($0) == nil }
            ?? false
        })
  }
  var current: [Touch] { s.touches.filter { $0.effort == s.index } }
  var marks: [Int] {
    (s.meet && s.reaction ? [-2] : []) + (s.meet && s.breakout ? [-1] : [])
      + s.marks(effort.set.metres)
  }
  func next(_ id: UUID) -> Int? {
    if s.outcome(id, s.index) != nil { return nil }
    return marks.first { mark in !current.contains { $0.swimmer == id && $0.mark == mark } }
  }
  var complete: Bool { !s.team.isEmpty && s.team.allSatisfy { next($0) == nil } }
  func record(_ id: UUID, _ seconds: Double?, method: String = "Hand-timed") {
    guard let mark = next(id) else { return }
    if let seconds, let previous = current.filter({ $0.swimmer == id }).compactMap(\.seconds).last,
      seconds <= previous
    {
      return
    }
    s.touches.append(
      Touch(
        swimmer: id, effort: s.index, mark: mark, seconds: seconds,
        method: seconds == nil ? "Untimed" : method))
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
  }
  func saveManual() {
    guard let id = manualID, let seconds = Double(manual), (0.001...86399).contains(seconds) else {
      return
    }
    let last = current.filter { $0.swimmer == id }.compactMap(\.seconds).last ?? 0
    if seconds > last { record(id, seconds, method: "Manual") }
  }
  func wake() {
    UIApplication.shared.isIdleTimerDisabled =
      phase == .active && !s.finished
      && ((s.started != nil && !complete) || (!s.meet && s.tempoAnchor != nil))
  }
  @ViewBuilder func tile(_ id: UUID) -> some View {
    let mark = next(id)
    Button {
      let t =
        s.elapsed() - Double((s.startSlots?[id] ?? s.team.firstIndex(of: id) ?? 0) * s.stagger)
      if t >= 0 { record(id, t) }
    } label: {
      VStack {
        if !s.lane(id).isEmpty { Text("Lane " + s.lane(id)).font(.caption.bold()) }
        Text(store.name(id)).font(.headline)
        Text(
          mark.map {
            $0 < 0 ? markName($0) : ($0 == marks.last ? "Finish \($0) m" : "Split \($0) m")
          } ?? s.outcome(id, s.index)?.title ?? "Finished")
        Text(current.last(where: { $0.swimmer == id })?.seconds.map(timeText) ?? "—")
          .monospacedDigit()
      }
      .frame(maxWidth: .infinity, minHeight: 92).foregroundStyle(.white).background(
        mark == nil
          ? Color.gray
          : [
            Color.indigo, Color(red: 0.60, green: 0.16, blue: 0.38),
            Color(red: 0.61, green: 0.25, blue: 0.03), Color(red: 0.17, green: 0.37, blue: 0.21),
          ][(s.team.firstIndex(of: id) ?? 0) % 4], in: RoundedRectangle(cornerRadius: 16)
      ).shadow(radius: 3, y: 3)
    }.buttonStyle(TilePress()).contextMenu {
      if s.meet { OutcomeActions(s: $s, swimmer: id, index: s.index) }
      if mark != nil {
        Button("Missed / untimed touch") { record(id, nil) }
        Button("Enter cumulative seconds") {
          manualID = id
          manual = ""
        }
      }
    }
  }
  func assignLane(_ lane: String, to id: UUID) {
    if !s.meet {
      var assigned = s.practiceLanes ?? [:]
      assigned[id] = lane
      s.practiceLanes = assigned
    }
    s.lanes[s.resultKey(id, s.index)] = lane
  }
  func laneMenu(_ id: UUID) -> some View {
    let current = s.lane(id)
    return Menu {
      Button("Unassigned") { assignLane("", to: id) }
      ForEach(1...8, id: \.self) { number in
        Button {
          assignLane(String(number), to: id)
        } label: {
          if current == String(number) {
            Label("Lane \(number)", systemImage: "checkmark")
          } else {
            Text("Lane \(number)")
          }
        }
      }
    } label: {
      HStack {
        Text(current.isEmpty ? "Select lane" : "Lane " + current)
        Image(systemName: "chevron.down")
      }.font(.subheadline.bold()).padding(8).background(.thinMaterial, in: Capsule())
    }.accessibilityLabel("Lane for " + store.name(id)).accessibilityValue(
      current.isEmpty ? "Unassigned" : current)
  }
  var checklist: some View {
    let efforts = s.efforts
    let done = s.completed
    return DisclosureGroup(s.meet ? "Race order" : "Workout order") {
      ForEach(s.sets) { item in
        let indices = efforts.indices.filter { efforts[$0].set.id == item.id }
        let count = indices.filter { done.contains($0) }.count
        Label(
          "\(item.section) · \(item.count) × \(item.metres) m \(item.title) · \(count)/\(indices.count)",
          systemImage: count == indices.count ? "checkmark.square.fill" : "square"
        ).frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
  func tempoBar(_ anchor: Date) -> some View {
    let choices = [30, 60, 90, 120]
    let interval = s.tempoSeconds.flatMap { choices.contains($0) ? $0 : nil } ?? 90
    return HStack(spacing: 8) {
      Text("Recovery tempo").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
      TimelineView(.periodic(from: .now, by: 0.12)) { context in
        let elapsed = max(0, context.date.timeIntervalSince(anchor))
        let fraction =
          1 - elapsed.truncatingRemainder(dividingBy: Double(interval)) / Double(interval)
        let left = tempoRemaining(anchor: anchor, now: context.date, interval: interval)
        let color: Color = left <= 10 ? .pink : fraction <= 0.5 ? .yellow : .cyan
        let angle = fraction * 2 * Double.pi - Double.pi / 2
        ZStack {
          Circle().stroke(.white.opacity(0.18), lineWidth: 6)
          Circle().trim(from: 0, to: fraction).stroke(
            color, style: StrokeStyle(lineWidth: 6, lineCap: .round)
          ).rotationEffect(.degrees(-90))
          Circle().fill(.white).frame(width: 9, height: 9).offset(
            x: 37 * cos(angle), y: 37 * sin(angle))
          Text("\(left)").font(.system(size: 36, weight: .black, design: .rounded))
            .monospacedDigit().foregroundStyle(.white)
        }.frame(width: 74, height: 74).accessibilityLabel("Recovery").accessibilityValue(
          "\(left) seconds")
      }
      HStack(spacing: 10) {
        Menu("\(interval) s") {
          ForEach(choices, id: \.self) { n in
            Button("\(n) seconds") {
              s.tempoSeconds = n
              s.tempoAnchor = Date()
            }
          }
        }
        Button {
          s.tempoAnchor = Date()
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }.accessibilityLabel("Restart recovery interval")
      }.frame(maxWidth: .infinity, alignment: .trailing)
    }.padding(.horizontal, 18).padding(.vertical, 9).frame(maxWidth: .infinity).foregroundStyle(
      .white
    ).tint(.cyan).background(Color(red: 0.035, green: 0.09, blue: 0.19))
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("\(s.venue) · \(s.course) m pool").foregroundStyle(.secondary)
        if !s.meet { checklist }
        if s.finished {
          if !s.meet {
            Label("Workout complete", systemImage: "checkmark.circle.fill").font(.title2)
          }
        } else {
          VStack(alignment: .leading, spacing: 6) {
            if !s.meet {
              Text(s.title).font(.title.bold())
              Text(
                "\(effort.set.section) · Round \(effort.round) of \(effort.set.rounds) · Rep \(effort.rep) of \(effort.set.count)"
              ).font(.subheadline.bold())
            }
            Text("\(effort.set.metres) m \(effort.set.title)").font(.title2.bold())
            let details = s.meet ? effort.set.raceLabel : effort.set.note
            if !details.isEmpty { Text(details) }
          }.padding().frame(maxWidth: .infinity, alignment: .leading).background(
            (s.meet ? Color.meetAccent : .practiceAccent).opacity(0.13),
            in: RoundedRectangle(cornerRadius: 16)
          ).overlay(
            RoundedRectangle(cornerRadius: 16).stroke(
              (s.meet ? Color.meetAccent : .practiceAccent).opacity(0.55)))
          if s.started == nil {
            if s.meet {
              MeetEntrants(item: $s.sets[raceIndex], roster: store.data.swimmers, showNames: false)
              ForEach(store.data.swimmers.filter { pendingTeam.contains($0.id) }) { sw in
                HStack {
                  VStack(alignment: .leading) {
                    Text(sw.name + " · " + sw.group)
                    if let issue = effort.set.entryIssue(sw) {
                      Text(issue + " · remove before starting").font(.caption)
                    }
                  }
                  Spacer()
                  laneMenu(sw.id)
                }
                let key = s.resultKey(sw.id, s.index)
                RaceEntry(name: sw.name, entry: s.entries[key] ?? "") { s.entries[key] = $0 }.id(
                  key)
              }
            } else {
              Text("Select swimmers").font(.headline)
              ForEach(store.data.swimmers) { sw in
                HStack {
                  Button {
                    if s.team.contains(sw.id) {
                      s.team.removeAll { $0 == sw.id }
                    } else {
                      s.team.append(sw.id)
                    }
                  } label: {
                    Label(
                      sw.name,
                      systemImage: s.team.contains(sw.id) ? "checkmark.circle.fill" : "circle")
                  }
                  Spacer()
                  if s.team.contains(sw.id) { laneMenu(sw.id) }
                }
              }
            }
            if store.data.swimmers.isEmpty { Text("Add swimmers from the home screen to begin.") }
            if s.meet {
              Toggle("Capture reaction", isOn: $s.reaction)
              Toggle("Capture breakout", isOn: $s.breakout)
            }
            if !s.meet { Stepper("Start spacing · \(s.stagger)s", value: $s.stagger, in: 0...60) }
            Button {
              if s.meet { s.team = pendingTeam }
              for id in s.team { s.lanes[s.resultKey(id, s.index)] = s.lane(id) }
              if !s.meet && s.tempoAnchor == nil { s.tempoAnchor = Date() }
              s.startSlots = nil
              s.uptime = ProcessInfo.processInfo.systemUptime
              s.started = Date()
            } label: {
              Text("Start").font(.largeTitle.bold()).frame(maxWidth: .infinity).padding()
            }.buttonStyle(.borderedProminent).disabled(!canStart)
          } else {
            Text(
              "Tap a swimmer at each mark. Hold a tile for manual entry, a missed touch, or meet outcomes."
            ).font(.footnote).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
              Text(timeText(complete ? current.compactMap(\.seconds).max() ?? 0 : s.elapsed()))
                .font(.largeTitle.monospacedDigit())
            }
            Toggle("Reverse lane order", isOn: $reverse)
            let columns = min(
              max(s.team.count, 1), UIDevice.current.userInterfaceIdiom == .pad ? 4 : 2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columns), spacing: 12)
            {
              ForEach(reverse ? Array(s.swimmersByLane.reversed()) : s.swimmersByLane, id: \.self) {
                id in
                tile(id)
              }
            }
            if let last = current.last {
              Button("Undo · \(store.name(last.swimmer)) · \(markName(last.mark))") {
                s.touches.removeAll { $0.id == last.id }
              }
            }
            Button("Cancel this effort", role: .destructive) { cancelRun = true }
            if complete {
              Button(
                s.meet
                  ? "Back to race programme"
                  : (s.completed.count + 1 == s.efforts.count
                    ? "Finish and view report" : "Next effort")
              ) {
                if s.meet {
                  s.finishSelectedRace()
                  dismiss()
                  return
                }
                var updated = s
                var done = s.completed
                done.insert(s.index)
                updated.completedIndices = done
                updated.started = nil
                updated.uptime = nil
                if let next = s.efforts.indices.first(where: { !done.contains($0) }) {
                  updated.index = next
                  if updated.meet { updated.team = [] }
                } else {
                  updated.finished = true
                  selectedRace = nil
                  report = !s.meet
                }
                s = updated
              }.buttonStyle(.borderedProminent)
            }
          }
        }
        if !s.touches.isEmpty {
          Button(s.meet ? "View race results and export" : "View results and export") {
            selectedRace = s.meet ? s.index : nil
            report = true
          }
        }
      }.padding().frame(maxWidth: .infinity, alignment: .leading)
    }.frame(maxWidth: .infinity, maxHeight: .infinity).safeAreaInset(edge: .bottom) {
      if !s.meet && !s.finished, let anchor = s.tempoAnchor { tempoBar(anchor) }
    }.sectionStyle(
      s.meet ? .meetAccent : .practiceAccent, strength: s.finished && s.meet ? 0.30 : 0.09
    ).navigationTitle(s.meet ? "\(effort.set.metres) m \(effort.set.title)" : s.title)
      .navigationBarBackButtonHidden(s.meet && s.started != nil && complete)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if !s.meet && s.started == nil { Button("Edit") { editing = true } }
      }
      .sheet(isPresented: $editing) { Editor(s: s) }
      .sheet(isPresented: $report) { NavigationStack { Results(s: $s, race: selectedRace) } }
      .alert(
        "Cumulative seconds",
        isPresented: Binding(get: { manualID != nil }, set: { if !$0 { manualID = nil } })
      ) {
        TextField("Seconds", text: $manual).keyboardType(.decimalPad)
        Button("Record") {
          saveManual()
          manualID = nil
        }
        Button("Cancel", role: .cancel) {}
      }
      .alert("Cancel this effort?", isPresented: $cancelRun) {
        Button("Discard this effort", role: .destructive) {
          s.touches.removeAll { $0.effort == s.index }
          s.started = nil
          s.uptime = nil
        }
        Button("Keep timing", role: .cancel) {}
      } message: {
        Text("Earlier efforts stay saved. This effort will return to the start screen.")
      }
      .onAppear {
        if s.meet && !s.finished && effort.set.entrants == nil {
          s.sets[raceIndex].entrants = s.team
          s.sets[raceIndex].entryGroup =
            store.data.swimmers.first(where: { $0.id == s.team.first })?.group
        }
        wake()
      }.onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
      .onChange(of: s.started) { wake() }.onChange(of: complete) { wake() }.onChange(of: phase) {
        wake()
      }
  }
}
struct TilePress: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1).animation(
      .easeOut(duration: 0.10), value: configuration.isPressed)
  }
}

struct RaceEntry: View {
  let name: String
  let entry: String
  let save: (String) -> Void
  @DeckState var open = false
  @DeckState var draftEntry = ""
  var body: some View {
    Button(entry.isEmpty ? "Add entry time" : "Entry time · " + entry) {
      draftEntry = entry
      open = true
    }
    .sheet(isPresented: $open) {
      NavigationStack {
        Form {
          TextField("Entry time (m:ss.xx)", text: $draftEntry)
        }
        .navigationTitle(name).toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { open = false } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              save(draftEntry)
              open = false
            }.disabled(!draftEntry.isEmpty && swimSeconds(draftEntry) == nil)
          }
        }
      }
    }
  }
}

struct OutcomeActions: View {
  @Binding var s: Session
  let swimmer: UUID, index: Int
  var body: some View {
    ForEach(RaceOutcome.allCases, id: \.rawValue) { outcome in
      Button(outcome.title) { s.setOutcome(swimmer, index, outcome) }
    }
    if s.outcome(swimmer, index) != nil {
      Button("Clear outcome") { s.setOutcome(swimmer, index, nil) }
    }
  }
}
