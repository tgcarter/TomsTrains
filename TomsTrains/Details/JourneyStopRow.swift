import SwiftUI

struct JourneyStopRow: View {
    let position: RoutePosition?
    let marksBoardStation: Bool
    let isAwaitingDepartureAtOrigin: Bool
    let stop: RouteStop
    let index: Int
    let stops: [RouteStop]

    var body: some View {
        let isFirst = index == 0
        let isLast = index == stops.count - 1
        let topPadding: CGFloat = isFirst ? 0 : 16
        let destinationIndex = stops.firstIndex(where: \.isDestination) ?? stops.count
        let onward = index > destinationIndex
        let reported = position?.last.id == stop.id
        let progress = position?.progress ?? -1
        let isBetweenStations = position?.isBetweenStations == true
        let completed = !stop.isCancelled && Double(index) <= progress
        let hasDeparted = stop.actualDeparture.map { $0 <= (stop.reportedAt ?? .distantPast) } == true
            || progress > Double(index)
        let progressColor = Color.accentColor
        let color: Color = stop.isCancelled ? .red : (completed ? progressColor : .secondary)
        let incomingColor: Color = Double(index) <= progress ? progressColor : .secondary
        let outgoingColor: Color = Double(index + 1) <= progress ? progressColor : .secondary
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(stop.name)
                    .fontWeight(stop.isBoarding || stop.isDestination ? .semibold : .regular)
                    .strikethrough(stop.isCancelled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(stop.timeLabel).monospacedDigit()
                    .foregroundStyle(stop.isCancelled ? Color.red : .primary)
                    .fixedSize()
            }
            if marksBoardStation && (stop.isDestination || stop.isBoarding) {
                Text("This Station").font(.caption).foregroundStyle(.tint)
            } else if stop.isDestination {
                Text(stop.isCancelled ? "Your Stop" : "Your Destination")
                    .font(.caption).foregroundStyle(stop.isCancelled ? Color.red : .accentColor)
            } else if stop.isBoarding && (stop.isCancelled || !hasDeparted) {
                Text(stop.isCancelled ? "Boarding Cancelled" : "Board Here")
                    .font(.caption).foregroundStyle(stop.isCancelled ? Color.red : .secondary)
            }
            if !stop.isCancelled {
                Text(stop.platform.flatMap { $0.isEmpty ? nil : "Platform \($0)" } ?? "Platform —")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(stop.timingLabel)
                .font(.caption).foregroundStyle(stop.timingStatus.color)
                .fixedSize(horizontal: false, vertical: true)
            if let scheduled = stop.differingScheduledTime {
                Text("Scheduled \(RailTime.string(scheduled))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if reported {
                Text(isBetweenStations ? "Departed" : "Last Reported Stop")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.top, topPadding)
        .padding(.bottom, isLast ? 0 : 16)
        .frame(maxWidth: .infinity, minHeight: isLast ? 0 : (isFirst ? 96 : 112), alignment: .topLeading)
        .padding(.leading, 42)
        .overlay(alignment: .leading) {
            // The rail takes the measured row height, including wrapped text and padding.
            GeometryReader { geometry in
                let markerY: CGFloat = topPadding + 12
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(index == 0 ? .clear : incomingColor)
                        .frame(width: 3, height: markerY)
                        .offset(x: 12.5)
                    Rectangle().fill(index == stops.count - 1 ? .clear : outgoingColor)
                        .frame(width: 3, height: max(0, geometry.size.height - markerY))
                        .offset(x: 12.5, y: markerY)
                    if reported && isBetweenStations {
                        Rectangle().fill(progressColor)
                            .frame(width: 3, height: max(0, geometry.size.height - markerY) / 2)
                            .offset(x: 12.5, y: markerY)
                    }
                    ZStack {
                        Circle().fill(Color(uiColor: .secondarySystemGroupedBackground))
                        if stop.isCancelled {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                        } else if isAwaitingDepartureAtOrigin || (reported && !isBetweenStations) {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(progressColor)
                        } else if completed {
                            Circle().fill(color)
                                .frame(width: stop.isDestination ? 18 : 12, height: stop.isDestination ? 18 : 12)
                        } else {
                            Circle().strokeBorder(color, lineWidth: stop.isDestination ? 4 : 2)
                                .frame(width: stop.isDestination ? 18 : 12, height: stop.isDestination ? 18 : 12)
                        }
                    }
                    .foregroundStyle(color).frame(width: 28, height: 28)
                    .offset(y: markerY - 14)
                    if reported && isBetweenStations {
                        Image(systemName: "tram.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(progressColor)
                            .frame(width: 28, height: 28)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .offset(y: markerY + (geometry.size.height - markerY) / 2 - 14)
                    }
                }
            }
            .frame(width: 28)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .foregroundStyle(onward ? .secondary : .primary)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isAwaitingDepartureAtOrigin ? "Awaiting departure report" : "")
    }


}

struct JourneyRouteSection: View {
    let stops: [RouteStop]
    let position: RoutePosition?
    let isCancelled: Bool
    var marksBoardStation = false

    var body: some View {
        let nextStop = stops.dropFirst().first { !$0.isCancelled }
        let isAwaitingDeparture = !isCancelled && position == nil
            && stops.first?.isAwaitingFirstDeparture(at: .now, nextStop: nextStop) == true
        Section {
            if stops.isEmpty {
                Text("Calling points unavailable").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        JourneyStopRow(position: position, marksBoardStation: marksBoardStation,
                            isAwaitingDepartureAtOrigin: index == 0 && isAwaitingDeparture, stop: stop, index: index, stops: stops)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } header: {
            Text("Route")
        } footer: {
            NationalRailAttribution()
        }
        .listSectionMargins(.vertical, 0)
    }
}
