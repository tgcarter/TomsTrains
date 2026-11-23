import SwiftUI

struct DepartureDetailView: View {
    let departure: Departure
    var tracker: TrainTracker? = nil
    var provider: any DepartureProviding = NationalRailProvider()
    @State private var detailedDeparture: Departure?
    @State private var locationError: String?
    @State private var isLoadingLocation = false
    @State private var showingAutoTracking = false
    private var service: Departure {
        if let tracked = tracker?.journeys.first(where: { $0.id == departure.id })?.departure { return tracked }
        return detailedDeparture?.mergingEarlierStops(from: departure) ?? departure
    }
    private var detailsKey: String {
        Bundle.main.object(forInfoDictionaryKey: "NationalRailQueryServicesAPIKey") as? String ?? ""
    }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ServiceSummaryView(summary: ServiceSummary(service: service, isTracked: tracker?.contains(service) == true),
                    isLoadingLocation: isLoadingLocation && detailedDeparture == nil, locationError: locationError)
                if let tracker, tracker.contains(service) || tracker.canStartTracking(service) {
                    Section {
                        Button {
                            tracker.toggle(service)
                        } label: {
                            Label(tracker.contains(service) ? "Stop Tracking" : "Track Train",
                                  systemImage: tracker.contains(service) ? "pin.slash" : "pin.fill")
                        }
                        if tracker.contains(service) {
                            Button("Configure Auto-Tracking", systemImage: "repeat") {
                                showingAutoTracking = true
                            }
                        }
                    } footer: {
                        Text(TrackedJourney(departure: service).hasArrived
                            ? "Arrived at your destination. This train stays on your board until the overnight reset."
                            : "Keeps this train on your board until the overnight reset. Live updates run while the app is open.")
                    }
                }
                JourneyRouteSection(stops: service.routeStops ?? [], position: service.routePosition,
                    isCancelled: service.isCancelledAtDestination)
            }
            .contentMargins(.vertical, 8, for: .scrollContent)
            .sheet(isPresented: $showingAutoTracking) {
                if let tracker {
                    AutoTrackingEditor(draft: tracker.autoRules.first { $0.matches(service) }
                        ?? AutoTrackingRule(departure: service), tracker: tracker)
                }
            }
            .pollingTrainDetails(when: !detailsKey.isEmpty && !detailsKey.contains("$("), refresh: refreshLocation)
            .navigationTitle("Train Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func refreshLocation() async {
        guard tracker?.contains(service) != true || TrackedJourney(departure: service).needsLiveDetails else {
            locationError = nil
            return
        }
        isLoadingLocation = true
        defer { isLoadingLocation = false }
        do {
            let updated = try await provider.serviceDetails(for: service)
            guard !Task.isCancelled else { return }
            let merged = updated.mergingEarlierStops(from: service)
            detailedDeparture = merged
            tracker?.receive(merged, fromLiveDetails: true)
            locationError = nil
        } catch {
            guard !Task.isCancelled else { return }
            locationError = service.isCancelledAtDestination ? nil : "Live update unavailable · showing last report"
        }
    }

}
