import Charts
import CoreText
import PDFKit
import SwiftUI
import UIKit

struct Results: View {
  @EnvironmentObject var store: Store
  @Binding var s: Session
  var race: Int? = nil
  var records: [Touch] { s.touches.filter { race == nil || $0.effort == race } }
  @DeckState var change: Touch?
  @DeckState var file: URL?
  @DeckState var summaryFile: URL?
  var body: some View {
    List {
      Text(
        "Times are grouped by effort. Share the CSV for analysis or the text summary for a swimmer."
      ).font(.footnote).foregroundStyle(.secondary)
      if let file { ShareLink("Share CSV", item: file) }
      if let summaryFile { ShareLink("Share text summary", item: summaryFile) }
      Section(race == nil ? "Session totals" : "Race totals") {
        LabeledContent(
          "Planned per swimmer",
          value: "\(race.map{s.efforts[$0].set.metres} ?? s.efforts.reduce(0){$0+$1.set.metres}) m")
        ForEach(
          Array(Set(records.map(\.swimmer))).sorted { $0.uuidString < $1.uuidString }, id: \.self
        ) { id in
          let distance = records.filter {
            $0.swimmer == id && $0.mark == s.efforts[$0.effort].set.metres
          }.reduce(0) { $0 + $1.mark }
          LabeledContent(store.name(id), value: "\(distance) m completed")
        }
      }
      let efforts = s.efforts
      ForEach(Array(Set(records.map(\.effort))).sorted(), id: \.self) { i in
        let e = efforts[i]
        Section("\(e.set.metres) m \(e.set.title) · Round \(e.round) · Rep \(e.rep)") {
          if s.meet {
            ForEach(
              Array(Set(records.filter { $0.effort == i }.map(\.swimmer))).sorted {
                $0.uuidString < $1.uuidString
              }, id: \.self
            ) { id in
              Menu(store.name(id) + " · " + (s.outcome(id, i)?.title ?? "Set race outcome")) {
                OutcomeActions(s: $s, swimmer: id, index: i)
              }
            }
          }
          ForEach(
            records.filter {
              s.outcome($0.swimmer, i) == nil && $0.effort == i && $0.mark == e.set.metres
            }
          ) { finish in
            if let seconds = finish.seconds {
              LabeledContent(store.name(finish.swimmer), value: timeText(seconds))
              LabeledContent(
                "Average per 50 m", value: timeText(seconds * 50 / Double(e.set.metres)))
              let key = s.resultKey(finish.swimmer, i)
              if s.meet {
                OfficialTime(value: s.official[key] ?? "") { s.official[key] = $0 }
                if let athlete = store.data.swimmers.first(where: { $0.id == finish.swimmer }),
                  athlete.bestCourse == s.course,
                  athlete.event.localizedCaseInsensitiveCompare("\(e.set.metres) m \(e.set.title)")
                    == .orderedSame,
                  let pb = swimSeconds(athlete.best)
                {
                  LabeledContent(
                    "Difference from profile PB",
                    value: String(format: "%+.2f s", (swimSeconds(s.official[key]) ?? seconds) - pb)
                  )
                }
              }
              if let entry = swimSeconds(s.entries[key]) {
                LabeledContent(
                  "Difference from entry", value: String(format: "%+.2f s", seconds - entry))
              }
              if let half = records.first(where: {
                $0.effort == i && $0.swimmer == finish.swimmer && $0.mark * 2 == e.set.metres
              })?.seconds {
                Text("First half \(timeText(half)) · Second half \(timeText(seconds-half))").font(
                  .caption)
              }
            }
          }
          ForEach(records.filter { $0.effort == i && RaceOutcome(rawValue: $0.mark) == nil }) {
            t in
            let previous = records.last {
              $0.effort == i && $0.swimmer == t.swimmer && $0.mark > 0 && $0.mark < t.mark
            }
            Button {
              change = t
            } label: {
              HStack {
                VStack(alignment: .leading) {
                  Text("\(store.name(t.swimmer)) · \(markName(t.mark))")
                  Text(t.seconds.map(timeText) ?? "Untimed").font(.headline.monospacedDigit())
                  if let time = t.seconds, let prev = previous?.seconds {
                    Text("Last \(t.mark-previous!.mark) m · \(timeText(time-prev))").font(.caption)
                  }
                }
                Spacer()
                Image(systemName: "pencil.circle")
              }
            }.buttonStyle(.plain)
          }
        }
      }
    }.sectionStyle(s.meet ? .meetAccent : .practiceAccent).navigationTitle(
      s.meet ? "Race results" : "Session results"
    ).sheet(item: $change) { touch in
      TouchEditor(s: $s, touch: touch)
    }.task(id: ExportRevision(touches: records, official: s.official)) {
      let efforts = s.efforts
      var rows = [
        [
          "Session", "Date", "Type", "Venue", "Pool (m)", "Swimmer ID", "Swimmer", "Event",
          "Instructions", "Round", "Repeat", "Distance (m)", "Capture mark", "Elapsed seconds",
          "Timing method", "Effort number", "Lane", "Entry time", "Official finish", "Race outcome",
        ]
      ]
      for t in records {
        let e = efforts[t.effort]
        rows.append([
          s.title, s.date.formatted(.iso8601), s.meet ? "Meet" : "Training", s.venue,
          String(s.course), t.swimmer.uuidString, store.name(t.swimmer), e.set.title,
          s.meet ? e.set.raceLabel : e.set.note,
          String(e.round), String(e.rep), String(e.set.metres), markName(t.mark),
          t.seconds.map { String(format: "%.2f", $0) } ?? "", t.method, String(t.effort + 1),
          s.lanes[s.resultKey(t.swimmer, t.effort)] ?? "",
          s.entries[s.resultKey(t.swimmer, t.effort)] ?? "",
          s.official[s.resultKey(t.swimmer, t.effort)] ?? "",
          s.outcome(t.swimmer, t.effort)?.title ?? "",
        ])
      }
      let csv = rows.map {
        $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(
          separator: ",")
      }.joined(separator: "\r\n")
      let url = FileManager.default.temporaryDirectory.appending(
        path: "Turnmark-\(s.id)-\(race.map(String.init) ?? "session").csv")
      do {
        try csv.write(to: url, atomically: true, encoding: .utf8)
        file = url
        let txt = url.deletingPathExtension().appendingPathExtension("txt")
        let lines = records.map { t in
          let e = efforts[t.effort]
          return
            "\(store.name(t.swimmer)) · \(e.set.title) \(s.meet ? e.set.raceLabel:e.set.note) · Round \(e.round), rep \(e.rep) · \(markName(t.mark)) · \(t.seconds.map(timeText) ?? "Untimed")"
        }
        try ([s.title, "\(s.date.formatted()) · \(s.venue) · \(s.course) m pool"] + lines).joined(
          separator: "\n"
        ).write(to: txt, atomically: true, encoding: .utf8)
        summaryFile = txt
      } catch { store.error = error.localizedDescription }
    }
  }
}
struct Sample: Identifiable {
  let id: UUID
  let date: Date
  let value: Double
  let key: String
  let session: String
}
struct Profile: View {
  @EnvironmentObject var store: Store
  let swimmer: Swimmer
  @DeckState var meet = false
  @DeckState var editing = false
  @DeckState var key = ""
  var samples: [Sample] {
    var rows = [Sample]()
    for s in store.data.sessions where s.meet == meet {
      let efforts = s.efforts
      for t in s.touches where t.swimmer == swimmer.id {
        let e = efforts[t.effort]
        if s.outcome(swimmer.id, t.effort) == nil, t.mark == e.set.metres, let value = t.seconds {
          rows.append(
            Sample(
              id: t.id, date: s.date,
              value: swimSeconds(s.official[s.resultKey(t.swimmer, t.effort)]) ?? value,
              key:
                "\(e.set.metres) m \(e.set.title) · \(s.course) m pool \(s.meet ? "" : e.set.note)",
              session: s.title))
        }
      }
    }
    return rows.sorted { $0.date < $1.date }
  }
  var body: some View {
    let current = store.data.swimmers.first { $0.id == swimmer.id } ?? swimmer
    let keys = Array(Set(samples.map(\.key))).sorted()
    let selected = keys.contains(key) ? key : keys.first ?? ""
    let rows = samples.filter { $0.key == selected }
    List {
      NavigationLink {
        ProgressReport(athlete: current)
      } label: {
        Label("Share progress · family or coach", systemImage: "doc.richtext")
      }
      Text("Choose training or meets to compare finishes for the same event and pool length.").font(
        .footnote
      ).foregroundStyle(.secondary)
      Text("\(current.group) · Age \(current.age)")
      LabeledContent(
        "Meet specializations",
        value: current.strokes.count == 5
          ? "All five events"
          : (current.strokes.isEmpty
            ? "Training only"
            : meetStrokes.filter { current.strokes.contains($0) }.joined(separator: ", ")))
      Picker("History", selection: $meet) {
        Text("Training").tag(false)
        Text("Meets").tag(true)
      }.pickerStyle(.segmented)
      if rows.isEmpty {
        Text("Completed times will appear here.")
      } else {
        Picker("Compare", selection: Binding(get: { selected }, set: { key = $0 })) {
          ForEach(keys, id: \.self) { Text($0).tag($0) }
        }
        Section("Performance") {
          Chart(rows) { r in PointMark(x: .value("Date", r.date), y: .value("Seconds", r.value)) }
            .frame(height: 150)
          let values = rows.map(\.value)
          LabeledContent("Best logged", value: timeText(values.min() ?? 0))
          LabeledContent("Average", value: timeText(values.reduce(0, +) / Double(rows.count)))
          LabeledContent(
            "Fastest to slowest spread", value: timeText((values.max() ?? 0) - (values.min() ?? 0)))
        }
        Section("History") {
          ForEach(rows.reversed()) { r in
            LabeledContent(
              "\(r.session) · \(r.date.formatted(date:.abbreviated,time:.omitted))",
              value: timeText(r.value))
          }
        }
      }
    }.sectionStyle(.rosterAccent).navigationTitle(current.name).toolbar {
      Button("Edit") { editing = true }
    }.sheet(
      isPresented: $editing
    ) { SwimmerForm(s: current) }
  }
}

struct OfficialTime: View {
  let value: String
  let save: (String) -> Void
  @DeckState var editing = false
  @DeckState var draft = ""
  var body: some View {
    Button(value.isEmpty ? "Add official finish" : "Official finish · " + value) {
      draft = value
      editing = true
    }
    .alert("Official finish", isPresented: $editing) {
      TextField("m:ss.xx", text: $draft)
      Button("Cancel", role: .cancel) {}
      Button("Save") { save(draft) }.disabled(!draft.isEmpty && swimSeconds(draft) == nil)
    }
  }
}

private struct ExportRevision: Equatable {
  let touches: [Touch]
  let official: [String: String]
}
struct TouchEditor: View {
  @Environment(\.dismiss) var dismiss
  @Binding var s: Session
  let touch: Touch
  @DeckState var draft = ""
  @DeckState var removing = false
  var valid: Bool {
    guard let value = swimSeconds(draft) else { return false }
    let related = s.touches.filter { $0.swimmer == touch.swimmer && $0.effort == touch.effort }
    return related.allSatisfy { other in
      guard let seconds = other.seconds else { return true }
      if other.mark < touch.mark { return seconds < value }
      if other.mark > touch.mark { return seconds > value }
      return true
    }
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("Cumulative time at " + markName(touch.mark)) {
          TextField("Seconds or m:ss.xx", text: $draft)
          Text("Enter elapsed time from the start, between the preceding and following captures.")
            .font(.caption)
        }
        Button("Delete capture", role: .destructive) { removing = true }
      }.navigationTitle("Edit capture").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            if let i = s.touches.firstIndex(where: { $0.id == touch.id }) {
              var row = s.touches[i]
              row.seconds = swimSeconds(draft)
              row.method = "Manual"
              s.touches[i] = row
            }
            dismiss()
          }.disabled(!valid)
        }
      }.onAppear { draft = touch.seconds.map(timeText) ?? "" }
        .alert("Delete this capture?", isPresented: $removing) {
          Button("Delete", role: .destructive) {
            s.touches.removeAll { $0.id == touch.id }
            dismiss()
          }
          Button("Cancel", role: .cancel) {}
        }
    }
  }
}

struct ProgressGroup: Identifiable {
  struct Swim {
    let session: UUID, date: Date, title: String, time: Double, method: String
    let halves: String?
  }
  let id: String
  let meet: Bool
  var swims: [Swim]
  var days: [[Swim]] {
    Dictionary(grouping: swims, by: { $0.session }).values.sorted {
      ($0[0].date, $0[0].session.uuidString) < ($1[0].date, $1[0].session.uuidString)
    }
  }
  func benchmark(_ swims: [Swim]) -> Double {
    let times = swims.map(\.time).sorted()
    if meet { return times[0] }
    return (times[(times.count - 1) / 2] + times[times.count / 2]) / 2
  }
  func summary(coach: Bool) -> [String] {
    let sessions = days
    guard let first = sessions.first, let last = sessions.last else { return [] }
    let latest = benchmark(last)
    let baseline = benchmark(first)
    let dates = last[0].date.formatted(date: .abbreviated, time: .omitted)
    let label = meet ? "fastest finish" : "middle repeat time"
    var lines = [
      "\(dates) · \(last[0].title): \(label) \(timeText(latest)) across \(last.count) timed \(last.count==1 ? "swim":"swims")."
    ]
    if sessions.count > 1 {
      let delta = latest - baseline
      let change =
        abs(delta) < 0.005
        ? "the same to the hundredth"
        : String(format: "%.2f seconds %@", abs(delta), delta < 0 ? "faster" : "slower")
      lines.append(
        "The latest \(label) was \(change) compared with \(first[0].date.formatted(date:.abbreviated,time:.omitted)) (\(timeText(baseline)))."
      )
    } else {
      lines.append(
        "This is the only recorded session in this comparison period. It sets a starting point for the next swim."
      )
    }
    if let best = swims.min(by: { $0.time < $1.time }), sessions.count > 1 {
      lines.append(
        "Fastest recorded in this period: " + timeText(best.time) + " on "
          + best.date.formatted(date: .abbreviated, time: .omitted) + ".")
    }
    if coach {
      let times = last.map(\.time)
      if times.count > 1 {
        lines.append(
          String(
            format: "Latest session range: %@ to %@, a %.2f-second spread.", timeText(times.min()!),
            timeText(times.max()!), times.max()! - times.min()!))
      }
      if let paced = last.min(by: { $0.time < $1.time }), let halves = paced.halves {
        lines.append("Deck splits for the fastest swim in this session: " + halves)
      }
      lines.append(
        "Timing sources in this comparison: "
          + Set(swims.map(\.method)).sorted().joined(separator: ", ") + ".")
    } else if !meet && last.count > 1 {
      let times = last.map(\.time)
      lines.append(
        String(
          format:
            "Across these repeats, the quickest and slowest finishes were %.2f seconds apart.",
          times.max()! - times.min()!))
    }
    return lines
  }
}
struct SwimmerProgress {
  var landLines = [String]()
  var groups = [ProgressGroup]()
  var outcomes = [String]()
  init(archive: Archive, swimmer: UUID, from: Date?) {
    for w in (archive.land ?? []).sorted(by: { $0.date < $1.date })
    where from.map({ w.date >= $0 }) ?? true {
      for e in w.exercises {
        let logs = w.logs.filter { $0.exercise == e.id && $0.swimmer == swimmer }.sorted {
          $0.number < $1.number
        }
        if !logs.isEmpty {
          let values = logs.map {
            "Set " + String($0.number) + ": " + String($0.quantity) + " " + e.unit
              + ($0.load.isEmpty ? "" : " at " + $0.load + " kg")
          }
          landLines.append(
            w.date.formatted(date: .abbreviated, time: .omitted) + " · " + w.title + " · " + e.name
              + " — " + values.joined(separator: ", "))
        }
      }
    }
    var byEvent = [String: ProgressGroup]()
    for session in archive.sessions.sorted(by: { $0.date < $1.date })
    where from.map({ session.date >= $0 }) ?? true {
      let efforts = session.efforts
      let records = Dictionary(
        grouping: session.touches.filter { $0.swimmer == swimmer }, by: \.effort)
      for (i, touches) in records.sorted(by: { $0.key < $1.key }) {
        let e = efforts[i].set
        if let result = touches.compactMap({ RaceOutcome(rawValue: $0.mark) }).first {
          outcomes.append(
            "\(session.date.formatted(date:.abbreviated,time:.omitted)) · \(session.title) · \(e.metres) m \(e.title): \(result.title)."
          )
          continue
        }
        guard let finish = touches.first(where: { $0.mark == e.metres }) else { continue }
        let official = swimSeconds(session.official[session.resultKey(swimmer, i)])
        guard let time = official ?? finish.seconds else { continue }
        let detail = session.meet || e.note.isEmpty ? "" : " · " + e.note
        let key =
          "\(session.meet ? "Meet" : "Training") · \(e.metres) m \(e.title)\(detail) · \(session.course) m pool"
        var halves: String?
        if let half = touches.first(where: { $0.mark * 2 == e.metres })?.seconds,
          let end = finish.seconds
        {
          halves = "\(timeText(half)) first half, \(timeText(end-half)) second half."
        }
        byEvent[key, default: ProgressGroup(id: key, meet: session.meet, swims: [])].swims.append(
          .init(
            session: session.id, date: session.date, title: session.title, time: time,
            method: official != nil ? "Official" : finish.method, halves: halves))
      }
    }
    groups = byEvent.values.sorted { $0.id < $1.id }
  }
}
struct ProgressReport: View {
  @EnvironmentObject var store: Store
  let athlete: Swimmer
  @DeckState var coach = false
  @DeckState var days = 0
  @DeckState var note = ""
  @DeckState var preview: ReportFile?
  var progress: SwimmerProgress {
    SwimmerProgress(
      archive: store.data, swimmer: athlete.id,
      from: days == 0
        ? nil
        : Calendar.current.date(
          byAdding: .day, value: 1 - days, to: Calendar.current.startOfDay(for: Date())))
  }
  var body: some View {
    let data = progress
    List {
      Picker("Audience", selection: $coach) {
        Text("Family").tag(false)
        Text("Coach").tag(true)
      }.pickerStyle(.segmented)
      Picker("Period", selection: $days) {
        Text("All history").tag(0)
        Text("Last 30 days").tag(30)
        Text("Last 90 days").tag(90)
      }
      if data.groups.isEmpty && data.outcomes.isEmpty && data.landLines.isEmpty {
        Text("No recorded results in this period.")
      }
      ForEach(data.groups) { group in
        Section(group.id) { ForEach(group.summary(coach: coach), id: \.self) { Text($0) } }
      }
      if !data.landLines.isEmpty {
        Section("Land training") {
          ForEach(Array(data.landLines.enumerated()), id: \.offset) { Text($0.element) }
        }
      }
      if !data.outcomes.isEmpty {
        Section("Race outcomes") {
          ForEach(Array(data.outcomes.enumerated()), id: \.offset) { Text($0.element) }
        }
      }
      Section("Coach’s note for this report") {
        TextField(
          "What did you notice? What will you work on together?", text: $note, axis: .vertical)
      }
      Button {
        do {
          preview = ReportFile(
            url: try progressPDF(athlete: athlete, data: data, coach: coach, days: days, note: note)
          )
        } catch { store.error = error.localizedDescription }
      } label: {
        Label("Preview and share PDF", systemImage: "square.and.arrow.up")
      }.disabled(data.groups.isEmpty && data.outcomes.isEmpty && data.landLines.isEmpty)
    }.sectionStyle(.rosterAccent).navigationTitle("Swimmer progress").sheet(item: $preview) {
      file in
      NavigationStack {
        PDFPreview(url: file.url).navigationTitle("Report preview").navigationBarTitleDisplayMode(
          .inline
        ).toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Close") { preview = nil } }
          ToolbarItem(placement: .primaryAction) {
            ShareLink(item: file.url) { Label("Share PDF", systemImage: "square.and.arrow.up") }
          }
        }
      }
    }
  }
}
struct ReportFile: Identifiable {
  let id = UUID()
  let url: URL
}
struct PDFPreview: UIViewRepresentable {
  let url: URL
  func makeUIView(context: Context) -> PDFView {
    let view = PDFView()
    view.autoScales = true
    view.document = PDFDocument(url: url)
    return view
  }
  func updateUIView(_ view: PDFView, context: Context) {}
}
func progressPDF(athlete: Swimmer, data: SwimmerProgress, coach: Bool, days: Int, note: String)
  throws -> URL
{
  let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let url = folder.appending(path: "Swimmer-progress.pdf")
  let body = NSMutableAttributedString(string: "")
  func append(_ text: String, _ size: CGFloat = 12, bold: Bool = false) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.paragraphSpacing = 7
    body.append(
      NSAttributedString(
        string: text + "\n",
        attributes: [
          .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
          .foregroundColor: UIColor.black, .paragraphStyle: paragraph,
        ]))
  }
  append(athlete.name, 26, bold: true)
  append(
    (coach ? "Coach performance report" : "Family progress report") + " · "
      + (days == 0 ? "All history" : "Last \(days) days"), 14)
  for group in data.groups {
    append(group.id, 15, bold: true)
    for line in group.summary(coach: coach) { append(line) }
    if coach {
      for swim in group.swims.sorted(by: { $0.date < $1.date }) {
        append(
          "\(swim.date.formatted(date:.abbreviated,time:.omitted)) · \(swim.title) · \(timeText(swim.time)) · \(swim.method)",
          10)
      }
    }
  }
  if !data.landLines.isEmpty {
    append("Land training", 15, bold: true)
    for line in data.landLines { append(line) }
  }
  if !data.outcomes.isEmpty {
    append("Race outcomes", 15, bold: true)
    for line in data.outcomes { append(line) }
  }
  if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    append("Coach’s note", 15, bold: true)
    append(note)
  }
  let setter = CTFramesetterCreateWithAttributedString(body)
  var bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
  guard let cg = CGContext(url as CFURL, mediaBox: &bounds, nil) else {
    throw CocoaError(.fileWriteUnknown)
  }
  var start = 0
  var page = 1
  while start < body.length {
    cg.beginPDFPage(nil)
    func caption(_ text: String, _ y: CGFloat) {
      let label = NSAttributedString(
        string: text,
        attributes: [.font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: UIColor.darkGray])
      cg.textPosition = CGPoint(x: 42, y: y)
      CTLineDraw(CTLineCreateWithAttributedString(label), cg)
    }
    caption("TURNMARK BY BLUE WHALES    /    " + athlete.name, 755)
    caption("\(Date().formatted(date:.abbreviated,time:.omitted))     ·     \(page)", 32)
    let path = CGPath(rect: CGRect(x: 42, y: 61, width: 528, height: 680), transform: nil)
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), path, nil)
    CTFrameDraw(frame, cg)
    cg.endPDFPage()
    let count = CTFrameGetVisibleStringRange(frame).length
    guard count > 0 else {
      cg.closePDF()
      throw CocoaError(.fileWriteUnknown)
    }
    start += count
    page += 1
  }
  cg.closePDF()
  return url
}
