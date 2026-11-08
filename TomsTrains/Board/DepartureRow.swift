import SwiftUI

struct DepartureRow: View {
    let departure: Departure
    let isNext: Bool
    var isEarlier = false
    var showsJourneyStatus = false
    private var displayedStatus: ServiceStatus { showsJourneyStatus ? departure.journeyStatus : departure.status }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isNext && !departure.isCancelledAtDestination {
                Text("EARLIEST ARRIVAL").font(.caption2.weight(.bold))
                    .tracking(1).foregroundStyle(.secondary)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { departureTime; arrivalTime }
                Text(departure.routeLabel).font(.headline)
                platform
                status
                operatorSummary
            } else {
                HStack(alignment: .center, spacing: 8) {
                    departureTime
                    if !departure.isCancelledAtDestination {
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        arrivalTime
                    }
                    Spacer(minLength: 0)
                    if let minutes = departure.journeyMinutes {
                        Text("\(minutes) min").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(departure.routeLabel).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    platform
                }
                HStack(alignment: .center) {
                    status
                    Spacer(minLength: 8)
                    operatorLabel
                }
            }
        }
        .padding(.vertical, 4)
        .saturation(isEarlier ? 0 : 1)
        .opacity(isEarlier ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var shownDepartureTime: Date {
        guard departure.status != .cancelled else { return departure.scheduled }
        if let actual = departure.routeStops?.first(where: \.isBoarding)?.actualDeparture {
            return actual
        }
        return departure.expected ?? departure.scheduled
    }

    private func timeColor(for status: ServiceStatus) -> Color {
        switch status {
        case .delayed: status.color
        case .early: .green
        default: .primary
        }
    }

    private var departureTime: some View {
        Text(RailTime.string(shownDepartureTime))
            .font(.title2.weight(.semibold)).monospacedDigit()
            .foregroundStyle(timeColor(for: departure.departureStatus))
            .strikethrough(departure.status == .cancelled)
            .accessibilityLabel("Departure \(RailTime.string(shownDepartureTime)), scheduled \(RailTime.string(departure.scheduled))")
    }

    @ViewBuilder private var arrivalTime: some View {
        if !departure.isCancelledAtDestination {
            let time = (departure.actualArrival ?? departure.expectedArrival).map(RailTime.string) ?? departure.arrivalLabel
            Text("ETA \(time)")
                .font(.subheadline.weight(.medium)).monospacedDigit()
                .foregroundStyle(timeColor(for: departure.journeyStatus))
        }
    }

    private var platform: some View {
        Text(departure.platform.map { "Platform \($0)" } ?? "Platform —")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var status: some View {
        if isEarlier {
            if departure.status == .cancelled {
                Label("Cancelled", systemImage: "xmark.circle")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            } else if let actual = departure.routeStops?.first(where: \.isBoarding)?.actualDeparture {
                Text("Departed \(RailTime.string(actual)) · \(departure.departureStatus.label)")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            } else {
                Text("Departure unconfirmed · \(departure.status.label)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
        HStack(spacing: 4) {
            Image(systemName: displayedStatus.symbol)
            Text(displayedStatus.label)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(displayedStatus.color)
        }
    }

    private var operatorLabel: some View {
        OperatorLogo(name: departure.operatorName, code: departure.operatorCode)
    }

    private var operatorSummary: some View {
        HStack(spacing: 4) {
            operatorLabel
            if let minutes = departure.journeyMinutes {
                Text("· \(minutes) min").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
