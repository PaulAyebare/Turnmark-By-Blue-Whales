import SwiftUI
import UniformTypeIdentifiers

@main struct TurnmarkApp: App {
  @StateObject private var store = Store()
  var body: some Scene {
    WindowGroup {
      NavigationStack {
        Home()
      }.environmentObject(store).tint(.indigo)
        .alert(
          "Storage issue",
          isPresented: Binding(get: { store.error != nil }, set: { _ in store.error = nil })
        ) {
          Button("OK") {}
        } message: {
          Text(store.error ?? "")
        }
    }
  }
}
struct Home: View {
  var body: some View {
    GeometryReader { geo in
      ZStack {
        LinearGradient(
          colors: [
            Color(red: 0.10, green: 0.06, blue: 0.21), Color(red: 0.20, green: 0.13, blue: 0.34),
          ], startPoint: .topLeading, endPoint: .bottomTrailing
        ).ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            Text("Turnmark by Blue Whales").font(
              .system(.largeTitle, design: .rounded, weight: .black)
            )
            .foregroundStyle(.white)
            NavigationLink {
              Roster()
            } label: {
              card(
                "Swimmers", "Manage your roster and review individual progress.", "person.2.fill",
                Color(red: 0.77, green: 0.95, blue: 0.30))
            }
            NavigationLink {
              Sessions(meet: false)
            } label: {
              card(
                "Training sessions", "Build a workout and time each repeat.", "stopwatch.fill",
                Color(red: 1, green: 0.60, blue: 0.32))
            }
            NavigationLink {
              LandSessions()
            } label: {
              card(
                "Land training", "Build workouts and log each swimmer’s sets.", "dumbbell.fill",
                Color(red: 0.46, green: 0.85, blue: 0.79))
            }
            NavigationLink {
              Sessions(meet: true)
            } label: {
              card(
                "Swim meets", "Set up races, capture splits and review finishes.", "flag.checkered",
                Color(red: 0.74, green: 0.64, blue: 1))
            }
            NavigationLink {
              BackupPanel()
            } label: {
              Label("Backup and restore", systemImage: "externaldrive").font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            }
            NavigationLink {
              AboutTurnmark()
            } label: {
              Label("About Turnmark", systemImage: "info.circle").font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            }
          }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity, minHeight: geo.size.height)
        }
      }
    }.toolbar(.hidden, for: .navigationBar)
  }
  func card(_ title: String, _ hint: String, _ icon: String, _ color: Color) -> some View {
    HStack(spacing: 16) {
      Image(systemName: icon).font(.title2).frame(width: 44, height: 44).background(
        .black.opacity(0.09), in: Circle())
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(.title3, design: .rounded, weight: .bold))
        Text(hint).font(.subheadline)
      }
      Spacer()
      Image(systemName: "chevron.right").font(.headline)
    }.multilineTextAlignment(.leading).padding(18).foregroundStyle(.black).background(
      color.gradient, in: RoundedRectangle(cornerRadius: 21)
    ).shadow(color: .black.opacity(0.24), radius: 5, y: 4)
  }
}
struct AboutTurnmark: View {
  var body: some View {
    List {
      Section {
        Text("Turnmark by Blue Whales").font(.title2.bold())
        Text("A coaching log for pool sessions, land workouts, swim meets, and swimmer progress.")
      }
      Section("Club partnership") {
        Text("Developed in consultation with Blue Whales Swim Club in Wakiso, Uganda.")
      }
    }.navigationTitle("About Turnmark")
  }
}
struct Roster: View {
  @EnvironmentObject var store: Store
  @DeckState var search = ""
  @DeckState var grouped = false
  @DeckState var adding = false
  @DeckState var removing: Swimmer?
  var body: some View {
    List {
      Text(
        "Add a swimmer to start timing. Open their name for results or swipe left to remove them."
      ).font(.subheadline).foregroundStyle(.secondary)
      Picker("Sort", selection: $grouped) {
        Text("Name").tag(false)
        Text("Age category").tag(true)
      }.pickerStyle(.segmented)
      ForEach(grouped ? ["U10", "U12", "U14", "U16", "U18", "18+"] : ["Roster"], id: \.self) {
        group in
        let swimmers = store.data.swimmers.filter {
          (!grouped || $0.group == group)
            && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }.sorted {
          ($0.last, $0.first) < ($1.last, $1.first)
        }
        if !swimmers.isEmpty {
          Section(group) {
            ForEach(swimmers) { s in
              NavigationLink(s.name) { Profile(swimmer: s) }.swipeActions(allowsFullSwipe: false) {
                Button("Delete", role: .destructive) { removing = s }
              }
            }
          }
        }
      }
    }.searchable(text: $search, prompt: "Find a swimmer").sectionStyle(.rosterAccent)
      .navigationTitle("Swimmers").toolbar { Button("Add swimmer") { adding = true } }.sheet(
        isPresented: $adding
      ) { SwimmerForm() }.alert(
        "Delete swimmer?",
        isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
        presenting: removing
      ) { swimmer in
        Button("Delete", role: .destructive) { store.removeSwimmer(swimmer.id) }
        Button("Cancel", role: .cancel) {}
      } message: { swimmer in
        Text("Remove " + swimmer.name + " and their recorded times from all sessions and meets?")
      }
  }
}
struct SwimmerForm: View {
  @EnvironmentObject var store: Store
  @Environment(\.dismiss) var dismiss
  @DeckState var s = Swimmer()
  var body: some View {
    NavigationStack {
      Form {
        TextField("First name", text: $s.first)
        TextField("Last name", text: $s.last)
        Stepper("Age · \(s.age)", value: $s.age, in: 1...110)
        Section {
          ForEach(meetStrokes, id: \.self) { stroke in
            Toggle(
              stroke,
              isOn: Binding(
                get: { s.strokes.contains(stroke) },
                set: { enabled in
                  var choices = s.strokes
                  if enabled { choices.insert(stroke) } else { choices.remove(stroke) }
                  s.raceSpecialties = choices
                }))
          }
        } header: {
          Text("Meet specializations")
        } footer: {
          Text(
            "Select every event this swimmer can race. All five are selected for a generalist. Pool training is open to everyone."
          )
        }
        Section("Optional") {
          TextField("Height (cm)", text: $s.height).keyboardType(.decimalPad)
          TextField("Weight (kg)", text: $s.weight).keyboardType(.decimalPad)
          TextField("Primary event", text: $s.event)
          TextField("Personal best (m:ss.xx)", text: $s.best)
          CoursePicker(course: $s.bestCourse)
        }
      }.sectionStyle(.rosterAccent).navigationTitle("Swimmer details").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            if let i = store.data.swimmers.firstIndex(where: { $0.id == s.id }) {
              store.data.swimmers[i] = s
            } else {
              store.data.swimmers.append(s)
            }
            dismiss()
          }.disabled(
            [s.first, s.last].contains {
              $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        }
      }
    }
  }
}
struct CoursePicker: View {
  @Binding var course: Int
  var body: some View {
    Picker("Pool length", selection: $course) {
      Text("25 m").tag(25)
      Text("50 m").tag(50)
    }
  }
}
struct Sessions: View {
  @EnvironmentObject var store: Store
  let meet: Bool
  @DeckState var draft: Session?
  @DeckState var removing: Session?
  var body: some View {
    List {
      Text(
        meet
          ? "Open a meet to time a race. Use the menu beside a meet to change its programme."
          : "Open a workout to select swimmers and start timing. Duplicate a session to reuse its sets."
      ).font(.subheadline).foregroundStyle(.secondary)
      Button(meet ? "New meet" : "New training session") { draft = Session(meet: meet) }
      ForEach(store.data.sessions.filter { $0.meet == meet }.sorted { $0.date > $1.date }) { s in
        HStack {
          NavigationLink {
            Deck(id: s.id)
          } label: {
            VStack(alignment: .leading) {
              Text(s.title)
              Text(
                "\(s.date.formatted(date:.abbreviated,time:.omitted)) · \(s.venue) · \(s.course) m"
              ).font(.caption)
            }
          }
          Menu {
            Button("Edit") { draft = s }.disabled(s.started != nil)
            Button("Delete", role: .destructive) { removing = s }
            Button("Duplicate") {
              var copy = Session(meet: meet)
              copy.title = s.title
              copy.venue = s.venue
              copy.course = s.course
              copy.sets = s.sets
              draft = copy
            }
          } label: {
            Image(systemName: "ellipsis.circle.fill").font(.title2)
          }.buttonStyle(.borderless).accessibilityLabel("Manage " + s.title)
        }
      }
    }.sectionStyle(meet ? .meetAccent : .practiceAccent).navigationTitle(
      meet ? "Swim meets" : "Training sessions"
    ).sheet(item: $draft) {
      Editor(s: $0)
    }.alert(
      "Delete this " + (meet ? "meet?" : "session?"),
      isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
      presenting: removing
    ) { item in
      Button("Delete", role: .destructive) { store.data.sessions.removeAll { $0.id == item.id } }
      Button("Cancel", role: .cancel) {}
    } message: { item in
      Text("This removes " + item.title + " and all of its timing results.")
    }
  }
}
struct Editor: View {
  @EnvironmentObject var store: Store
  @Environment(\.dismiss) var dismiss
  @DeckState var confirmChanges = false
  @DeckState var s: Session
  var body: some View {
    NavigationStack {
      Form {
        TextField(s.meet ? "Meet name" : "Session name", text: $s.title)
        DatePicker("Date", selection: $s.date, displayedComponents: .date)
        TextField("Location", text: $s.venue)
        Menu("Saved locations") {
          ForEach(Array(Set(store.data.sessions.map(\.venue))).sorted(), id: \.self) { venue in
            Button(venue) {
              s.venue = venue
              s.course = store.data.sessions.last { $0.venue == venue }?.course ?? 25
            }
          }
        }
        CoursePicker(course: $s.course).onChange(of: s.course) { _, newCourse in
          if s.meet && newCourse == 50 {
            for i in s.sets.indices where s.sets[i].metres == 25 { s.sets[i].metres = 50 }
          }
        }
        Section(s.meet ? "Races" : "Workout") {
          Text("Expand a row to change or remove it. Save applies your changes.").font(.footnote)
            .foregroundStyle(.secondary)
          EditButton()
          if !s.meet {
            Menu("Add from workout menu") {
              Button("Complete workout") {
                s.sets += workout.map {
                  var item = $0
                  item.id = UUID()
                  return item
                }
              }
              ForEach(workout) { item in
                Button(
                  "\(item.section) · \(item.count) × \(item.metres) m \(item.title) \(item.note)"
                ) {
                  var copy = item
                  copy.id = UUID()
                  copy.block = UUID()
                  s.sets.append(copy)
                }
              }
            }
          }
          Button(s.meet ? "Add race" : "Add custom set") {
            s.sets.append(
              .init(
                section: s.meet ? "Race" : "Training", title: "Freestyle", count: 1, metres: 100,
                entrants: s.meet ? [] : nil, stage: s.meet ? "Heat" : nil, heat: s.meet ? 1 : nil))
          }
          let planned = s.efforts
          let recorded = Set(
            s.touches.compactMap {
              planned.indices.contains($0.effort) ? planned[$0.effort].set.id : nil
            })
          ForEach($s.sets) { $item in
            DisclosureGroup("\(item.count) × \(item.metres) m · \(item.title)") {
              Button(s.meet ? "Remove race" : "Remove set", role: .destructive) {
                let id = item.id
                s.sets.removeAll { $0.id == id }
              }
              if s.meet {
                Picker("Stroke / event", selection: $item.title) {
                  if !meetStrokes.contains(item.title) { Text(item.title).tag(item.title) }
                  ForEach(meetStrokes, id: \.self) { Text($0).tag($0) }
                }
                if !recorded.contains(item.id) {
                  MeetEntrants(item: $item, roster: store.data.swimmers)
                }
                let choices = meetDistances(course: s.course)
                Picker("Race distance", selection: $item.metres) {
                  if !choices.contains(item.metres) {
                    Text("\(item.metres) m · existing").tag(item.metres)
                  }
                  ForEach(choices, id: \.self) { Text("\($0) m").tag($0) }
                }
                Picker(
                  "Heat / race",
                  selection: Binding(get: { item.stage ?? "Heat" }, set: { item.stage = $0 })
                ) {
                  ForEach(["Heat", "Timed final", "Semifinal", "Final", "Time trial"], id: \.self) {
                    Text($0).tag($0)
                  }
                }
                Stepper(
                  "Heat number · \(item.heat ?? 1)",
                  value: Binding(get: { item.heat ?? 1 }, set: { item.heat = $0 }), in: 1...999)
                if !item.note.isEmpty { TextField("Existing race notes", text: $item.note) }
              } else {
                TextField("Drill", text: $item.title)
                TextField("Instructions", text: $item.note)
                Stepper("\(item.metres) m", value: $item.metres, in: 25...5000, step: 25)
                Stepper("Repeats · \(item.count)", value: $item.count, in: 1...100)
                Stepper(
                  "Block rounds · \(item.rounds)",
                  value: Binding(
                    get: { item.rounds },
                    set: { n in
                      let block = item.block
                      for i in s.sets.indices where s.sets[i].block == block {
                        s.sets[i].rounds = n
                      }
                    }), in: 1...20)
              }
            }
          }.onDelete { s.sets.remove(atOffsets: $0) }.onMove {
            s.sets.move(fromOffsets: $0, toOffset: $1)
          }
        }
        Text("Planned distance · \(s.efforts.reduce(0){$0+$1.set.metres}) m")
      }.sectionStyle(s.meet ? .meetAccent : .practiceAccent).navigationTitle(
        s.meet ? "Meet details" : "Session builder"
      ).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            if let old = store.data.sessions.first(where: { $0.id == s.id }), !old.touches.isEmpty,
              old.sets != s.sets || old.course != s.course
            {
              confirmChanges = true
            } else {
              save()
            }
          }.disabled(s.title.isEmpty || s.venue.isEmpty)
        }
      }.alert("Update recorded programme?", isPresented: $confirmChanges) {
        Button("Save changes") { save() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Removing a race or repeat removes its times. Changing its distance clears its times. Changing pool length clears all times. Other results stay with their original race."
        )
      }
    }
  }
  func save() {
    if let i = store.data.sessions.firstIndex(where: { $0.id == s.id }) {
      store.data.sessions[i] = s.reconciled(with: store.data.sessions[i])
    } else {
      store.data.sessions.append(s)
    }
    dismiss()
  }

}
typealias DeckState<Value> = SwiftUI.State<Value>

extension View {
  func sectionStyle(_ accent: Color, strength: Double = 0.09) -> some View {
    scrollContentBackground(.hidden).background {
      ZStack {
        Color(uiColor: .systemGroupedBackground)
        accent.opacity(strength)
      }.ignoresSafeArea()
    }.tint(accent).toolbarBackground(accent.opacity(0.14), for: .navigationBar)
  }
}
extension Color {
  static let rosterAccent = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? .systemGreen : UIColor(red: 0.25, green: 0.40, blue: 0.04, alpha: 1)
    })
  static let practiceAccent = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? .systemOrange : UIColor(red: 0.59, green: 0.27, blue: 0.08, alpha: 1)
    })
  static let meetAccent = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? .systemPurple : UIColor(red: 0.42, green: 0.26, blue: 0.62, alpha: 1)
    })
}
struct BackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var bytes: Data
  init(_ archive: Archive) throws { bytes = try JSONEncoder().encode(BackupPayload(archive)) }
  init(configuration: ReadConfiguration) throws {
    guard let bytes = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    self.bytes = bytes
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: bytes)
  }
}
struct BackupPanel: View {
  @EnvironmentObject var store: Store
  @DeckState var doc: BackupDocument?
  @DeckState var exporting = false
  @DeckState var importing = false
  @DeckState var pending: Archive?
  @DeckState var confirm = false
  @DeckState var message = ""
  var body: some View {
    List {
      Section("Full team archive") {
        Text(
          "Save swimmers, workouts, meets and results together. For a report about one swimmer, use Share progress on their profile."
        )
        Button("Save backup to Files") {
          do {
            doc = try BackupDocument(store.data)
            exporting = true
          } catch { message = error.localizedDescription }
        }
        Button("Restore from Files") { importing = true }
        if !message.isEmpty { Text(message) }
      }
    }.navigationTitle("Backup and restore")
      .fileExporter(
        isPresented: $exporting, document: doc, contentType: .json,
        defaultFilename: "Turnmark-backup"
      ) { result in
        switch result {
        case .success: message = "Backup saved."
        case .failure(let error): message = error.localizedDescription
        }
      }
      .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
        do {
          let url = try result.get()
          let granted = url.startAccessingSecurityScopedResource()
          defer { if granted { url.stopAccessingSecurityScopedResource() } }
          pending = try JSONDecoder().decode(BackupPayload.self, from: Data(contentsOf: url))
            .checked()
          confirm = true
        } catch { message = "Could not restore the file. " + error.localizedDescription }
      }
      .alert("Replace current team data?", isPresented: $confirm) {
        Button("Cancel", role: .cancel) { pending = nil }
        Button("Restore", role: .destructive) {
          if let pending {
            do {
              try store.restore(pending)
              message = "Team archive restored."
            } catch { message = error.localizedDescription }
          }
          pending = nil
        }
      } message: {
        Text(
          "The backup contains \(pending?.swimmers.count ?? 0) swimmers and \(pending?.sessions.count ?? 0) pool sessions and meets, plus \(pending?.land?.count ?? 0) land workouts. Restoring replaces this device’s team archive."
        )
      }
  }
}

let drylandMenu: [(String, [(String, String)])] = [
  ("Cardio", [("Stationary bike", "minutes"), ("Run", "minutes"), ("Rowing machine", "metres")]),
  ("Strength", [("Squat", "reps"), ("Band row", "reps"), ("Push-up", "reps")]),
  ("Core", [("Dead bug", "reps"), ("Side plank", "seconds"), ("Bird dog", "reps")]),
  ("Mobility", [("Thoracic rotation", "reps"), ("Shoulder mobility", "minutes")]),
  ("Balance and coordination", [("Single-leg balance", "seconds"), ("Skipping", "seconds")]),
  ("Other", []),
]
struct LandSessions: View {
  @EnvironmentObject var store: Store
  @DeckState var draft: LandWorkout?
  @DeckState var removal: LandWorkout?
  var body: some View {
    List {
      Button("Build land workout") { draft = LandWorkout() }
      ForEach((store.data.land ?? []).sorted { $0.date > $1.date }) { w in
        HStack {
          NavigationLink {
            LandDetail(id: w.id)
          } label: {
            VStack(alignment: .leading) {
              Text(w.title)
              Text(
                "\(w.date.formatted(date:.abbreviated,time:.omitted)) · \(w.exercises.count) exercises"
              ).font(.caption)
            }
          }
          Menu {
            Button("Edit workout") { draft = w }
            Button("Duplicate plan") {
              var copy = w
              copy.id = UUID()
              copy.date = Date()
              copy.logs = []
              copy.athletes = []
              draft = copy
            }
            Button("Delete", role: .destructive) { removal = w }
          } label: {
            Image(systemName: "ellipsis.circle")
          }.buttonStyle(.borderless)
        }
      }
    }.sectionStyle(.teal).navigationTitle("Land training").sheet(item: $draft) {
      LandEditor(plan: $0)
    }
    .alert(
      "Delete workout and logged sets?",
      isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
      presenting: removal
    ) { w in
      Button("Delete", role: .destructive) { store.data.land?.removeAll { $0.id == w.id } }
      Button("Cancel", role: .cancel) {}
    }
  }
}
struct LandEditor: View {
  @EnvironmentObject var store: Store
  @Environment(\.dismiss) var dismiss
  @DeckState var plan: LandWorkout
  var body: some View {
    NavigationStack {
      Form {
        TextField("Workout name", text: $plan.title)
        DatePicker("Date", selection: $plan.date, displayedComponents: .date)
        TextField("Location", text: $plan.venue)
        Section("Exercises") {
          Menu("Add exercise") {
            ForEach(drylandMenu.indices, id: \.self) { i in
              let category = drylandMenu[i]
              Menu(category.0) {
                ForEach(category.1.indices, id: \.self) { j in
                  let example = category.1[j]
                  Button(example.0) {
                    plan.exercises.append(
                      .init(category: category.0, name: example.0, unit: example.1))
                  }
                }
                Button("Custom exercise") {
                  plan.exercises.append(.init(category: category.0, name: "Custom exercise"))
                }
              }
            }
          }
          ForEach($plan.exercises) { $e in
            let logged = plan.logs.contains { $0.exercise == e.id }
            DisclosureGroup(e.name + " · " + String(e.sets) + " sets") {
              TextField("Exercise", text: $e.name)
              Picker("Category", selection: $e.category) {
                ForEach(drylandMenu.indices, id: \.self) { i in
                  Text(drylandMenu[i].0).tag(drylandMenu[i].0)
                }
              }
              Picker("Track by", selection: $e.unit) {
                ForEach(["reps", "seconds", "minutes", "metres"], id: \.self) { Text($0) }
              }.disabled(logged)
              Stepper(
                "Sets · \(e.sets)", value: $e.sets,
                in: max(1, plan.logs.filter { $0.exercise == e.id }.map(\.number).max() ?? 1)...100)
              HStack {
                Text("Target per set (\(e.unit))")
                TextField("Target", value: $e.target, format: .number).multilineTextAlignment(
                  .trailing
                ).keyboardType(.numberPad)
              }
              if !logged {
                Button("Remove exercise", role: .destructive) {
                  let id = e.id
                  plan.exercises.removeAll { $0.id == id }
                }
              }
            }
          }
        }
        Section("Participating swimmers") {
          ForEach(store.data.swimmers) { sw in
            Button {
              if plan.athletes.contains(sw.id) {
                plan.athletes.removeAll { $0 == sw.id }
              } else {
                plan.athletes.append(sw.id)
              }
            } label: {
              Label(
                sw.name,
                systemImage: plan.athletes.contains(sw.id) ? "checkmark.square.fill" : "square")
            }.disabled(plan.logs.contains { $0.swimmer == sw.id })
          }
        }
      }.sectionStyle(.teal).navigationTitle("Land workout").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            store.saveLand(plan)
            dismiss()
          }.disabled(
            plan.title.trimmingCharacters(in: .whitespaces).isEmpty || plan.exercises.isEmpty
              || plan.exercises.contains {
                $0.name.trimmingCharacters(in: .whitespaces).isEmpty || $0.target < 1
              })
        }
      }
    }
  }
}
struct LandDetail: View {
  @EnvironmentObject var store: Store
  let id: UUID
  @DeckState var draft: LandWorkout?
  @DeckState var logging: LandLog?
  var body: some View {
    if let w = store.data.land?.first(where: { $0.id == id }) {
      List {
        Text(
          "Select a set to record what the swimmer completed. Tap a checked set to make a correction."
        ).font(.subheadline)
        if w.athletes.isEmpty { Button("Select swimmers") { draft = w } }
        ForEach(w.exercises) { e in
          Section(e.category + " · " + e.name) {
            Text("Plan · \(e.sets) × \(e.target) \(e.unit)").font(.headline)
            ForEach(w.athletes, id: \.self) { athlete in
              DisclosureGroup(store.name(athlete)) {
                ForEach(1...e.sets, id: \.self) { number in
                  let entry = w.logs.first {
                    $0.swimmer == athlete && $0.exercise == e.id && $0.number == number
                  }
                  Button {
                    logging =
                      entry
                      ?? LandLog(
                        swimmer: athlete, exercise: e.id, number: number, quantity: e.target,
                        load: "")
                  } label: {
                    Label(
                      "Set \(number) · "
                        + (entry.map {
                          "\($0.quantity) \(e.unit)"
                            + ($0.load.isEmpty ? "" : " · " + $0.load + " kg")
                        } ?? "Log set"),
                      systemImage: entry == nil ? "square" : "checkmark.square.fill")
                  }
                }
              }
            }
          }
        }
      }.sectionStyle(.teal).navigationTitle(w.title).toolbar { Button("Edit") { draft = w } }
        .sheet(item: $draft) { LandEditor(plan: $0) }
        .sheet(item: $logging) { log in
          LandSetForm(
            workout: id, log: log, unit: w.exercises.first { $0.id == log.exercise }?.unit ?? "reps"
          )
        }
    }
  }
}
struct LandSetForm: View {
  @EnvironmentObject var store: Store
  @Environment(\.dismiss) var dismiss
  let workout: UUID
  @DeckState var log: LandLog
  let unit: String
  var body: some View {
    NavigationStack {
      Form {
        Text(store.name(log.swimmer)).font(.headline)
        LabeledContent("Completed " + unit) {
          TextField("Actual", value: $log.quantity, format: .number).multilineTextAlignment(
            .trailing
          ).keyboardType(.numberPad)
        }
        TextField("Optional load (kg)", text: $log.load).keyboardType(.decimalPad)
        if store.data.land?.first(where: { $0.id == workout })?.logs.contains(where: {
          $0.id == log.id
        }) == true {
          Button("Clear logged set", role: .destructive) { commit(remove: true) }
        }
      }.sectionStyle(.teal).navigationTitle("Set \(log.number)").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { commit(remove: false) }.disabled(
            log.quantity < 0
              || (!log.load.isEmpty && !(Double(log.load).map { $0.isFinite && $0 >= 0 } ?? false)))
        }
      }
    }
  }
  func commit(remove: Bool) {
    guard var w = store.data.land?.first(where: { $0.id == workout }) else { return }
    w.logs.removeAll {
      $0.swimmer == log.swimmer && $0.exercise == log.exercise && $0.number == log.number
    }
    if !remove { w.logs.append(log) }
    store.saveLand(w)
    dismiss()
  }
}

struct MeetEntrants: View {
  @Binding var item: SetItem
  let roster: [Swimmer]
  var showNames = true
  var body: some View {
    let chosen = item.entrants ?? []
    let sorted = roster.sorted { ($0.last, $0.first) < ($1.last, $1.first) }
    VStack(alignment: .leading, spacing: 6) {
      Menu {
        ForEach(sorted) { sw in
          let selected = chosen.contains(sw.id)
          let issue = item.entryIssue(sw)
          Button {
            item.toggleEntrant(sw)
          } label: {
            Label(
              sw.name + " · " + sw.group + (issue.map { " · " + $0 } ?? ""),
              systemImage: selected ? "checkmark.circle.fill" : "circle")
          }.disabled(!selected && issue != nil)
        }
      } label: {
        Label(
          chosen.isEmpty
            ? "Select race swimmers" : "Change race swimmers · " + (item.entryGroup ?? ""),
          systemImage: "chevron.down.circle.fill")
      }.disabled(sorted.isEmpty)
      if sorted.isEmpty {
        Text("Add a swimmer to the roster first.").font(.caption)
      } else if chosen.isEmpty && !sorted.contains(where: { item.entryIssue($0) == nil }) {
        Text(
          "No eligible swimmers. Check the race stroke or edit a swimmer’s meet specializations in Swimmers."
        ).font(.caption)
      } else if chosen.isEmpty {
        Text("Choose the first entrant to set this race’s age category.").font(.caption)
      } else if showNames {
        ForEach(sorted.filter { chosen.contains($0.id) }) { sw in
          Text(
            sw.name + " · " + sw.group
              + (item.entryIssue(sw).map { " · " + $0 + " — remove before starting" } ?? "")
          ).font(.subheadline)
        }
      }
    }
  }
}
