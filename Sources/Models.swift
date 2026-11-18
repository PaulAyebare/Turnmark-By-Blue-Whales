import Foundation
import SwiftUI

struct Swimmer: Identifiable, Codable {
  var id = UUID()
  var first = "", last = "", age = 12
  var height = "", weight = "", event = "", best = "", bestCourse = 25
  var raceSpecialties: Set<String>?
  var strokes: Set<String> { raceSpecialties ?? Set(meetStrokes) }
  var name: String { first + " " + last }
  var group: String { [10, 12, 14, 16, 18].first(where: { age < $0 }).map { "U\($0)" } ?? "18+" }
}
struct SetItem: Identifiable, Codable, Equatable {
  var id = UUID()
  var section: String
  var title: String
  var count: Int
  var metres: Int
  var rounds = 1
  var note = ""
  var entrants: [UUID]?
  var entryGroup: String?
  func entryIssue(_ swimmer: Swimmer) -> String? {
    if let entryGroup, swimmer.group != entryGroup { return "Requires " + entryGroup }
    let aliases = [
      "free": "Freestyle", "fly": "Butterfly", "back": "Backstroke", "breast": "Breaststroke",
      "im": "Individual Medley (IM)", "individual medley": "Individual Medley (IM)",
    ]
    let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let stroke = aliases[normalized] ?? meetStrokes.first { $0.lowercased() == normalized }
    guard let stroke else { return "Choose a stroke for this race" }
    return swimmer.strokes.contains(stroke) ? nil : "Outside specializations"
  }
  mutating func toggleEntrant(_ swimmer: Swimmer) {
    var selected = entrants ?? []
    if selected.contains(swimmer.id) {
      selected.removeAll { $0 == swimmer.id }
    } else {
      guard entryIssue(swimmer) == nil else { return }
      if selected.isEmpty { entryGroup = swimmer.group }
      selected.append(swimmer.id)
    }
    entrants = selected
    if selected.isEmpty { entryGroup = nil }
  }
  var stage: String?
  var heat: Int?
  var raceLabel: String {
    [
      stage == "Heat" && heat != nil ? nil : stage, heat.map { "Heat " + String($0) },
      note.isEmpty ? nil : note,
    ].compactMap { $0 }.joined(
      separator: " · ")
  }
  var block = UUID()
}
let workout: [SetItem] = {
  let main = UUID()
  return [
    .init(section: "Warm Up", title: "Freestyle", count: 4, metres: 25, note: "Build"),
    .init(
      section: "Drill Set", title: "Catch-up + swim", count: 4, metres: 50,
      note: "25 m catch-up + 25 m swim"),
    .init(
      section: "Drill Set", title: "Backstroke", count: 4, metres: 25,
      note: "6:4 for 25 + one-arm drill for 25. Switch arms next round."),
    .init(
      section: "Drill Set", title: "Breaststroke", count: 4, metres: 25,
      note: "2:1 for 25 + 8 cycles per 25"),
    .init(
      section: "Main Set", title: "Underwater kicks", count: 4, metres: 25, rounds: 4, block: main),
    .init(
      section: "Main Set", title: "Kickout + swim", count: 4, metres: 25, rounds: 4, block: main),
    .init(
      section: "Main Set", title: "Underwater kicks", count: 4, metres: 25, rounds: 4, block: main),
    .init(
      section: "Main Set", title: "Freestyle", count: 1, metres: 25, rounds: 4, note: "90%",
      block: main),
    .init(
      section: "Main Set", title: "Freestyle", count: 1, metres: 25, rounds: 4, note: "Max",
      block: main),
    .init(section: "Speed", title: "Freestyle", count: 1, metres: 50, note: "Max with fins"),
    .init(section: "Cool Down", title: "Freestyle", count: 1, metres: 50, note: "PB & Pd"),
  ]
}()
struct Effort {
  var programmeKey: String { "\(set.id)/\(round)/\(rep)" }
  var set: SetItem
  var round: Int
  var rep: Int
}
struct Touch: Codable, Identifiable, Equatable {
  var id = UUID()
  var swimmer: UUID
  var effort: Int
  var mark: Int
  var seconds: Double?
  var method = "Hand-timed"
}
struct Session: Identifiable, Codable {
  var id = UUID()
  var meet: Bool
  var title = "", venue = "", course = 25
  var date = Date()
  var sets = [SetItem](), team = [UUID](), touches = [Touch]()
  var index = 0, stagger = 0
  var started: Date?
  var uptime: Double?
  var startSlots: [UUID: Int]?
  var tempoAnchor: Date?
  var tempoSeconds: Int?
  var reaction = false, breakout = false
  var entries = [String: String]()
  var practiceLanes: [UUID: String]?
  var lanes = [String: String]()
  var official = [String: String]()
  func resultKey(_ swimmer: UUID, _ effort: Int) -> String { "\(effort)-\(swimmer.uuidString)" }
  var programmeOrder: [String]?
  func programmeIndices(for efforts: [Effort]) -> [Int] {
    guard let programmeOrder else { return Array(efforts.indices) }
    let indices = Dictionary(uniqueKeysWithValues: efforts.indices.map { (efforts[$0].programmeKey, $0) })
    var remaining = Set(efforts.indices)
    let ordered = programmeOrder.compactMap { indices[$0].flatMap { remaining.remove($0) } }
    return ordered + efforts.indices.filter { remaining.contains($0) }
  }
  var completedIndices: Set<Int>?
  var completed: Set<Int> { completedIndices ?? (finished ? Set(efforts.indices) : Set(0..<index)) }
  var finished = false
  var efforts: [Effort] {
    var result = [Effort]()
    var i = 0
    while i < sets.count {
      var end = i + 1
      while end < sets.count && sets[end].block == sets[i].block { end += 1 }
      for round in 1...sets[i].rounds {
        for set in sets[i..<end] {
          for rep in 1...set.count { result.append(Effort(set: set, round: round, rep: rep)) }
        }
      }
      i = end
    }
    return result
  }
  mutating func selectRace(_ race: Int, roster: [Swimmer]) -> Bool {
    let programme = efforts
    guard meet, programme.indices.contains(race), !completed.contains(race),
      started == nil || race == index
    else { return false }
    // In older archives, index also encodes how many races were completed in order.
    completedIndices = completed
    if started == nil {
      if programme.indices.contains(index),
        let previous = sets.firstIndex(where: { $0.id == programme[index].set.id }),
        sets[previous].entrants == nil
      {
        sets[previous].entrants = team
        sets[previous].entryGroup = roster.first { $0.id == team.first }?.group
      }
      index = race
      team = sets.first { $0.id == programme[race].set.id }?.entrants ?? []
    }
    return true
  }
  mutating func finishSelectedRace() {
    guard meet, started != nil else { return }
    var done = completed
    done.insert(index)
    completedIndices = done
    finished = done.count == efforts.count
    started = nil
    uptime = nil
  }
  func marks(_ distance: Int) -> [Int] {
    Array(stride(from: course, to: distance, by: course)) + [distance]
  }
  func elapsed() -> Double {
    guard let started else { return 0 }
    let wall = Date().timeIntervalSince(started)
    if let uptime {
      let delta = ProcessInfo.processInfo.systemUptime - uptime
      if delta >= 0 && abs(delta - wall) < 60 { return delta }
    }
    return max(0, wall)
  }
}
struct Archive: Codable {
  var swimmers = [Swimmer](), sessions = [Session]()
  var land: [LandWorkout]?
}
@MainActor final class Store: ObservableObject {
  @Published var error: String?
  private var readable = true
  let url = URL.applicationSupportDirectory.appending(path: "RaceDeck.json")
  @Published var data = Archive() {
    didSet {
      guard readable else { return }
      do {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(data).write(to: url, options: .atomic)
      } catch { self.error = error.localizedDescription }
    }
  }
  init() {
    if FileManager.default.fileExists(atPath: url.path) {
      do { data = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url)) } catch {
        readable = false
        self.error = "Could not open the saved archive. " + error.localizedDescription
      }
    }
  }
  func restore(_ archive: Archive) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(archive).write(to: url, options: .atomic)
    readable = false
    data = archive
    readable = true
  }
  func name(_ id: UUID) -> String { data.swimmers.first { $0.id == id }?.name ?? "Swimmer" }
}
func timeText(_ value: Double) -> String {
  let ticks = Int((max(0, value) * 100).rounded())
  return String(format: "%d:%02d.%02d", ticks / 6000, ticks / 100 % 60, ticks % 100)
}

func markName(_ mark: Int) -> String {
  if let outcome = RaceOutcome(rawValue: mark) { return outcome.title }
  if mark == -2 { return "Reaction" }
  if mark == -1 { return "Breakout" }
  return "\(mark) m"
}

func swimSeconds(_ text: String?) -> Double? {
  guard let text else { return nil }
  let pieces = text.split(separator: ":", omittingEmptySubsequences: false)
  guard pieces.count == 1 || pieces.count == 2, let tail = Double(pieces.last ?? ""), tail.isFinite,
    tail >= 0
  else { return nil }
  let minutes = pieces.count == 2 ? Int(pieces[0]) : 0
  guard let minutes, minutes >= 0, minutes < 1440, pieces.count == 1 || tail < 60 else {
    return nil
  }
  let total = Double(minutes) * 60 + tail
  return total > 0 && total < 86400 ? total : nil
}

extension Session {
  func reconciled(with original: Session) -> Session {
    let old = original.efforts
    let new = efforts
    func identity(_ e: Effort) -> String { "\(e.set.id)/\(e.round)/\(e.rep)/\(e.set.metres)" }
    let positions = Dictionary(
      uniqueKeysWithValues: new.enumerated().map { (identity($0.element), $0.offset) })
    var indices = [Int: Int]()
    if course == original.course {
      for (i, e) in old.enumerated() { indices[i] = positions[identity(e)] }
    }
    var result = self
    result.touches = original.touches.compactMap { t in
      guard let index = indices[t.effort] else { return nil }
      var updated = t
      updated.effort = index
      return updated
    }
    func remap(_ values: [String: String]) -> [String: String] {
      var output = [String: String]()
      for (key, value) in values {
        let parts = key.split(separator: "-", maxSplits: 1)
        if parts.count == 2, let i = Int(parts[0]), let mapped = indices[i] {
          output["\(mapped)-\(parts[1])"] = value
        }
      }
      return output
    }
    result.entries = remap(original.entries)
    result.lanes = remap(original.lanes)
    result.official = remap(original.official)
    let previousDone = original.completed
    let done = Set(indices.compactMap { previousDone.contains($0.key) ? $0.value : nil })
    result.completedIndices = done
    result.finished = new.indices.allSatisfy { done.contains($0) }
    result.index = new.indices.first { !done.contains($0) } ?? max(0, new.count - 1)
    return result
  }
}
extension Store {
  func removeSwimmer(_ id: UUID) {
    var archive = data
    if var workouts = archive.land {
      for i in workouts.indices {
        workouts[i].athletes.removeAll { $0 == id }
        workouts[i].logs.removeAll { $0.swimmer == id }
      }
      archive.land = workouts
    }
    archive.swimmers.removeAll { $0.id == id }
    for i in archive.sessions.indices {
      var s = archive.sessions[i]
      if s.started != nil && s.team.contains(id) {
        // Freeze each remaining swimmer's original start slot before changing the roster.
        if s.startSlots == nil {
          s.startSlots = Dictionary(
            uniqueKeysWithValues: s.team.enumerated().map { ($0.element, $0.offset) })
        }
      }
      for j in s.sets.indices where s.sets[j].entrants?.contains(id) == true {
        s.sets[j].entrants?.removeAll { $0 == id }
        if s.sets[j].entrants?.isEmpty == true { s.sets[j].entryGroup = nil }
      }
      s.team.removeAll { $0 == id }
      s.touches.removeAll { $0.swimmer == id }
      s.startSlots?.removeValue(forKey: id)
      s.practiceLanes?.removeValue(forKey: id)
      if s.team.isEmpty {
        s.started = nil
        s.uptime = nil
      }
      s.entries = s.entries.filter { !$0.key.hasSuffix(id.uuidString) }
      s.official = s.official.filter { !$0.key.hasSuffix(id.uuidString) }
      s.lanes = s.lanes.filter { !$0.key.hasSuffix(id.uuidString) }
      archive.sessions[i] = s
    }
    data = archive
  }
}

enum RaceOutcome: Int, CaseIterable {
  case dns = -5
  case dnf = -4
  case dq = -3
  var title: String {
    switch self {
    case .dns: return "Did not start"
    case .dnf: return "Did not finish"
    case .dq: return "Disqualified"
    }
  }
}
extension Session {
  func outcome(_ swimmer: UUID, _ effort: Int) -> RaceOutcome? {
    touches.first {
      $0.effort == effort && $0.swimmer == swimmer && RaceOutcome(rawValue: $0.mark) != nil
    }.flatMap { RaceOutcome(rawValue: $0.mark) }
  }
  mutating func setOutcome(_ swimmer: UUID, _ effort: Int, _ outcome: RaceOutcome?) {
    touches.removeAll {
      $0.effort == effort && $0.swimmer == swimmer && RaceOutcome(rawValue: $0.mark) != nil
    }
    if let outcome {
      touches.append(
        Touch(
          swimmer: swimmer, effort: effort, mark: outcome.rawValue, seconds: nil,
          method: "Race outcome"))
    }
  }
  func lane(_ swimmer: UUID) -> String {
    lanes[resultKey(swimmer, index)] ?? (meet ? "" : practiceLanes?[swimmer] ?? "")
  }
  var swimmersByLane: [UUID] {
    team.enumerated().sorted {
      let a = Int(lane($0.element)) ?? Int.max
      let b = Int(lane($1.element)) ?? Int.max
      return a == b ? $0.offset < $1.offset : a < b
    }.map(\.element)
  }
}
struct BackupPayload: Codable {
  let version: Int
  let archive: Archive
  init(_ archive: Archive) {
    version = 3
    self.archive = archive
  }
  func checked() throws -> Archive {
    let invalid = CocoaError(.fileReadCorruptFile)
    let swimmerIDs = Set(archive.swimmers.map(\.id))
    guard (1...3).contains(version), swimmerIDs.count == archive.swimmers.count,
      Set(archive.sessions.map(\.id)).count == archive.sessions.count
    else { throw invalid }
    for s in archive.sessions {
      for item in s.sets {
        if let entrants = item.entrants {
          guard Set(entrants).count == entrants.count, Set(entrants).isSubset(of: swimmerIDs) else {
            throw invalid
          }
        }
      }
      guard [25, 50].contains(s.course),
        s.sets.allSatisfy({
          (1...100).contains($0.count) && (1...20).contains($0.rounds)
            && (1...5000).contains($0.metres)
        }), Set(s.sets.map(\.id)).count == s.sets.count,
        s.sets.reduce(0, { $0 + $1.rounds * $1.count }) <= 100000,
        Set(s.team).isSubset(of: swimmerIDs), Set(s.team).count == s.team.count,
        (0...60).contains(s.stagger)
      else { throw invalid }
      let n = s.efforts.count
      guard (0..<max(n, 1)).contains(s.index),
        s.touches.allSatisfy({
          (0..<n).contains($0.effort) && swimmerIDs.contains($0.swimmer)
            && ($0.seconds.map { (0...86400).contains($0) } ?? true)
        })
      else { throw invalid }
    }
    let workouts = archive.land ?? []
    guard Set(workouts.map(\.id)).count == workouts.count else { throw invalid }
    for w in workouts {
      guard Set(w.athletes).isSubset(of: swimmerIDs), Set(w.athletes).count == w.athletes.count,
        Set(w.exercises.map(\.id)).count == w.exercises.count,
        w.exercises.allSatisfy({ (1...100).contains($0.sets) && $0.target > 0 }),
        w.logs.allSatisfy({ log in
          w.athletes.contains(log.swimmer) && log.quantity >= 0
            && w.exercises.contains { $0.id == log.exercise && (1...$0.sets).contains(log.number) }
        })
      else { throw invalid }
    }
    return archive
  }
}

let meetStrokes = [
  "Freestyle", "Backstroke", "Breaststroke", "Butterfly", "Individual Medley (IM)",
]
func meetDistances(course: Int) -> [Int] {
  (course == 25 ? [25] : []) + Array(stride(from: 50, through: 5000, by: 50))
}
struct LandExercise: Identifiable, Codable {
  var id = UUID(), category = "Strength", name = "", sets = 1, target = 1, unit = "reps"
}
struct LandLog: Identifiable, Codable {
  var id = UUID()
  var swimmer: UUID
  var exercise: UUID
  var number: Int
  var quantity: Int
  var load: String
}
struct LandWorkout: Identifiable, Codable {
  var id = UUID(), title = "", venue = "", date = Date(), exercises = [LandExercise](),
    athletes = [UUID](), logs = [LandLog]()
}
extension Store {
  func saveLand(_ workout: LandWorkout) {
    var items = data.land ?? []
    if let i = items.firstIndex(where: { $0.id == workout.id }) {
      items[i] = workout
    } else {
      items.append(workout)
    }
    data.land = items
  }
}

func tempoRemaining(anchor: Date, now: Date, interval: Int) -> Int {
  interval - Int(max(0, now.timeIntervalSince(anchor))) % interval
}
