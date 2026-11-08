import SwiftUI

struct ServiceSummaryView: View {
    let summary: ServiceSummary
    var isLoadingLocation = false
    var locationError: String?
    private var service: Departure { summary.service }
    private var statusPanelColor: Color {
        service.isCancelledAtDestination ? .red : summary.status.color
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.title).font(.title2.bold())
                if let position = summary.position {
                    Text(position).font(.subheadline).foregroundStyle(.secondary)
                }
                if !service.isCancelledAtDestination && isLoadingLocation {
                    ProgressView("Locating train…").font(.subheadline)
                }
                if let locationError {
                    Text(locationError).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
            .listRowInsets(.vertical, 8)
            if !summary.showsStatusPanel {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Image(systemName: summary.status.symbol)
                        Text(summary.status.label)
                    }
                    .foregroundStyle(summary.status.color)
                }
            }
            LabeledContent("Scheduled Departure", value: RailTime.string(service.scheduled))
            if let actual = summary.actualDeparture {
                LabeledContent("Departed", value: RailTime.string(actual))
            } else if let expected = summary.expectedDeparture {
                LabeledContent("Expected Departure", value: RailTime.string(expected))
            }
            if let arrival = service.scheduledArrival {
                LabeledContent("Scheduled Arrival", value: RailTime.string(arrival))
            }
            if !service.isCancelledAtDestination {
                if let actual = service.actualArrival {
                    LabeledContent("Arrived", value: RailTime.string(actual))
                } else if let expected = summary.expectedArrival {
                    LabeledContent("Expected Arrival", value: RailTime.string(expected))
                }
            }
            LabeledContent("Platform", value: service.platform ?? "Not announced")
            LabeledContent("Operator") {
                OperatorLogo(name: service.operatorName, code: service.operatorCode, height: 32)
            }
            .listRowInsets(.vertical, 4)
        } footer: {
            if let observed = service.observedAt {
                Text("Updated \(RailTime.string(observed))")
            }
        }
        if summary.showsStatusPanel {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: summary.status.symbol)
                        Text(summary.status.label)
                    }
                    .font(.headline)
                    if let reason = summary.reason {
                        Text(reason)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .foregroundStyle(statusPanelColor)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(statusPanelColor.opacity(0.12))
        }
    }
}
