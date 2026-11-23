import SwiftUI

struct ServiceSummaryView: View {
    private struct Event {
        let scheduled: Date?
        let actual: Date?
        let expected: Date?
    }

    private let title: String
    private let station: String?
    private let position: String?
    private let status: ServiceStatus
    private let statusLabel: String
    private let reason: String?
    private let departure: Event?
    private let arrival: Event?
    private let platform: String?
    private let operatorName: String
    private let operatorCode: String?
    private let observedAt: Date?
    private let isLoadingLocation: Bool
    private let locationError: String?

    init(summary: ServiceSummary, isLoadingLocation: Bool = false, locationError: String? = nil) {
        let service = summary.service
        let arrivalInferred = summary.hasArrived && service.actualArrival == nil
        title = summary.title
        station = nil
        position = summary.position
        status = arrivalInferred ? .onTime : summary.status
        statusLabel = arrivalInferred ? "Arrived" : summary.status.label
        reason = summary.showsStatusPanel ? summary.reason : nil
        departure = Event(scheduled: service.scheduled, actual: summary.actualDeparture, expected: summary.expectedDeparture)
        arrival = Event(scheduled: service.scheduledArrival, actual: service.isCancelledAtDestination ? nil : service.actualArrival,
            expected: summary.expectedArrival)
        platform = service.platform
        operatorName = service.operatorName
        operatorCode = service.operatorCode
        observedAt = service.observedAt
        self.isLoadingLocation = isLoadingLocation
        self.locationError = locationError
    }

    init(train: LiveStationTrain, mode: LiveBoardMode, station: Station, locationError: String? = nil) {
        title = train.headline
        self.station = station.name
        position = train.position?.label
        status = train.status
        statusLabel = train.statusLabel(for: mode)
        reason = train.reason
        let event = Event(scheduled: train.scheduled, actual: train.actual, expected: train.expected)
        departure = mode == .departures ? event : nil
        arrival = mode == .arrivals ? event : nil
        platform = train.platform
        operatorName = train.operatorName
        operatorCode = train.operatorCode
        observedAt = train.observedAt
        isLoadingLocation = false
        self.locationError = locationError
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title2.bold())
                if let station {
                    Text(station).font(.subheadline).foregroundStyle(.secondary)
                }
                if let position {
                    Text(position).font(.subheadline).foregroundStyle(.secondary)
                }
                if status != .cancelled && isLoadingLocation {
                    ProgressView("Locating train…").font(.subheadline)
                }
                if let locationError {
                    Text(locationError).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
            .listRowInsets(.vertical, 8)
            LabeledContent("Status") {
                Label(statusLabel, systemImage: status.symbol)
                    .labelStyle(CompactStatusLabelStyle())
                    .foregroundStyle(status.color)
            }
            if let departure { times(departure, scheduled: "Scheduled Departure", actual: "Departed", expected: "Expected Departure") }
            if let arrival { times(arrival, scheduled: "Scheduled Arrival", actual: "Arrived", expected: "Expected Arrival") }
            LabeledContent("Platform", value: platform ?? "Not announced")
            LabeledContent("Operator") {
                OperatorLogo(name: operatorName, code: operatorCode, height: 32)
            }
            .listRowInsets(.vertical, 4)
        } footer: {
            if let observedAt {
                Text("Updated \(RailTime.string(observedAt))")
            }
        }
        if let reason, !reason.isEmpty {
            Section {
                Text(reason)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(status.color)
                    .padding(.vertical, 6)
            }
            .listRowBackground(status.color.opacity(0.12))
        }
    }

    @ViewBuilder private func times(_ event: Event, scheduled: LocalizedStringKey,
                                    actual: LocalizedStringKey, expected: LocalizedStringKey) -> some View {
        if let time = event.scheduled {
            LabeledContent(scheduled, value: RailTime.string(time))
        }
        if let time = event.actual {
            LabeledContent(actual, value: RailTime.string(time))
        } else if let time = event.expected, event.scheduled.map({
            !JourneyDirection.londonCalendar.isDate(time, equalTo: $0, toGranularity: .minute)
        }) ?? true {
            LabeledContent(expected, value: RailTime.string(time))
        }
    }
}
