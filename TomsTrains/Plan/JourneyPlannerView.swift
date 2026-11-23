import SwiftUI

struct JourneyPlannerView: View {
    private enum Endpoint: String, Identifiable {
        case from = "From"
        case to = "To"

        var id: Self { self }
    }

    private struct Form: Equatable {
        var from: Station?
        var to: Station?
        var mode: JourneySearchMode = .leaveNow
        var time = Date.now
    }

    private struct Search: Equatable {
        let id = UUID()
        let from: String
        let to: String
        let mode: JourneySearchMode
        let time: Date
    }

    private static let stationIDs: [String: String] = {
        guard let url = Bundle.main.url(forResource: "JourneyStationIDs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let stations = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return stations
    }()

    @State private var form = Form()
    @State private var picking: Endpoint?
    @State private var search: Search?
    @State private var journeys: [PlannedJourney]?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                DepartureBoardHeader(title: "Plan")
                Section {
                    stationButton(.from, station: form.from)
                    stationButton(.to, station: form.to)
                    Picker("When", selection: $form.mode) {
                        ForEach(JourneySearchMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if form.mode != .leaveNow {
                        DatePicker("Date and time", selection: $form.time,
                                   in: JourneyDirection.londonCalendar.startOfDay(for: .now)...)
                            .environment(\.calendar, JourneyDirection.londonCalendar)
                            .environment(\.timeZone, JourneyDirection.londonCalendar.timeZone)
                    }
                    Button("Find Journeys", action: findJourneys)
                        .disabled(form.from == nil || form.to == nil || form.from == form.to || isSearching)
                } footer: {
                    if !showsResults { BoardFooter(branding: .journeyPlanner) }
                }
                .listSectionMargins(.top, 0)
                if showsResults { results }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $picking) { endpoint in
                NavigationStack {
                    StationPicker(title: endpoint.rawValue, selection: .single { station in
                        switch endpoint {
                        case .from: form.from = station
                        case .to: form.to = station
                        }
                    })
                }
            }
            .onChange(of: form) { _, _ in
                search = nil
                journeys = nil
                message = nil
            }
            .task(id: search) {
                if let search, journeys == nil, message == nil { await load(search) }
            }
        }
    }

    private var isSearching: Bool { search != nil && journeys == nil && message == nil }
    private var showsResults: Bool { isSearching || journeys != nil || message != nil }

    private func stationButton(_ endpoint: Endpoint, station: Station?) -> some View {
        Button { picking = endpoint } label: {
            HStack {
                Text(endpoint.rawValue).foregroundStyle(.primary)
                Spacer()
                Text(station?.name ?? "Choose station").foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(endpoint.rawValue)
        .accessibilityValue(station?.name ?? "Choose station")
    }

    private var results: some View {
        Section {
            if let message {
                Text(message).foregroundStyle(.secondary)
            } else if let journeys, let search, let from = form.from, let to = form.to {
                if journeys.isEmpty {
                    Text("No rail journeys found for this time. Try another time or date.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(journeys.indices, id: \.self) { index in
                        let journey = journeys[index]
                        JourneyResultRow(journey: journey, travelDate: search.time,
                            bookingURL: journey.bookingURL(from: from, to: to), expanded: index == 0)
                    }
                    .id(search.id)
                }
            } else if isSearching {
                ProgressView("Finding journeys…")
            }
        } header: {
            if journeys != nil { Text("Journeys") }
        } footer: {
            BoardFooter(branding: .journeyPlanner)
        }
    }

    private func findJourneys() {
        journeys = nil
        search = nil
        message = nil
        guard let from = form.from, let to = form.to, from != to else { return }
        guard let originID = Self.stationIDs[from.rawValue], let destinationID = Self.stationIDs[to.rawValue] else {
            message = JourneyPlanningProvider.Failure.stationUnavailable.errorDescription
            return
        }
        let now = Date.now
        let calendar = JourneyDirection.londonCalendar
        let currentMinute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let chosenMinute = calendar.dateInterval(of: .minute, for: form.time)?.start ?? form.time
        guard form.mode == .leaveNow || chosenMinute >= currentMinute else {
            message = "Choose a date and time from now onwards."
            return
        }
        search = Search(from: originID, to: destinationID, mode: form.mode,
                        time: form.mode == .leaveNow ? now : chosenMinute)
    }

    private func load(_ active: Search) async {
        do {
            let results = try await JourneyPlanningProvider().journeys(
                from: active.from, to: active.to, mode: active.mode, time: active.time)
            guard !Task.isCancelled, search == active else { return }
            journeys = results
        } catch {
            guard !Task.isCancelled, search == active else { return }
            message = (error as? JourneyPlanningProvider.Failure)?.errorDescription
                ?? JourneyPlanningProvider.Failure.unavailable.errorDescription
        }
    }
}

private struct JourneyResultRow: View {
    let journey: PlannedJourney
    let travelDate: Date
    let bookingURL: URL
    @State var expanded: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            layout {
                Button {
                    expanded.toggle()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text("\(clock(journey.startTime)) → \(clock(journey.endTime))")
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Depart \(clock(journey.startTime)), arrive \(clock(journey.endTime)), \(summary)")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")

                Link(destination: bookingURL) {
                    Label("Book", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Book \(clock(journey.startTime)) journey on Railsmartr")
            }
            .padding(.vertical, 6)

            if expanded {
                let legs = journey.legs.filter { $0.isTrain || $0.changesStationOnFoot }
                ForEach(legs.indices, id: \.self) { index in
                    let leg = legs[index]
                    Divider()
                    if index > 0, legs[index - 1].isTrain, leg.isTrain, leg.interlineWithPreviousLeg != true {
                        let transfer = leg.startTime.timeIntervalSince(legs[index - 1].endTime)
                        Text(transfer > 0 ? "\(duration(transfer)) to change trains" : "Change trains")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 9)
                    }
                    legRow(leg)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var summary: String {
        let changes = switch journey.changes {
        case 0: "Direct"
        case 1: "1 change"
        default: "\(journey.changes) changes"
        }
        return "\(duration(journey.duration)) · \(changes)"
    }

    private func legRow(_ leg: PlannedJourney.Leg) -> some View {
        layout {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                stop(leg.from.name, at: leg.startTime)
                stop(leg.to.name, at: leg.endTime)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Leave \(leg.from.name) at \(clock(leg.startTime)), reach \(leg.to.name) at \(clock(leg.endTime))")

            if leg.isTrain {
                OperatorLogo(name: leg.operatorName, code: leg.operatorCode, height: 26)
            } else {
                Label("Walk", systemImage: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Walk between stations")
            }
        }
        .padding(.vertical, 10)
    }

    private func stop(_ station: String, at date: Date) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(RailTime.string(date))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                if let day = differentDay(date) {
                    Text(day).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(station)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func clock(_ date: Date) -> String {
        let time = RailTime.string(date)
        return differentDay(date).map { "\($0) \(time)" } ?? time
    }

    private func differentDay(_ date: Date) -> String? {
        let calendar = JourneyDirection.londonCalendar
        guard !calendar.isDate(date, inSameDayAs: travelDate) else { return nil }
        var day = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_GB"))
        day.timeZone = calendar.timeZone
        return date.formatted(day)
    }
}
