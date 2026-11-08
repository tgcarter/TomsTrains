import SwiftUI

struct DepartureDetailView: View {
    let departure: Departure
    var tracker: TrainTracker? = nil
    var provider: any DepartureProviding = NationalRailProvider()
    @State private var detailedDeparture: Departure?
    @State private var locationError: String?
    @State private var isLoadingLocation = false
    @State private var showingAutoTracking = false
    @Environment(\.scenePhase) private var scenePhase
    private var service: Departure {
        let tracked = tracker?.journeys.first(where: { $0.id == departure.id })?.departure
        return [detailedDeparture, tracked].compactMap { $0 }.reduce(departure) {
            $1.mergingEarlierStops(from: $0)
        }
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
                if !service.isServiceComplete, let tracker {
                    Section {
                        Button {
                            tracker.toggle(service)
                        } label: {
                            Label(tracker.contains(service) ? "Stop Tracking" : "Track Train",
                                  systemImage: tracker.contains(service) ? "pin.slash" : "pin.fill")
                        }
                        .disabled(TrackedJourney(departure: service).hasArrived)
                        if tracker.contains(service) {
                            Button("Configure Auto-Tracking", systemImage: "repeat") {
                                showingAutoTracking = true
                            }
                        }
                    } footer: {
                        Text(TrackedJourney(departure: service).hasArrived
                            ? "Arrived at your destination. Tracking has ended."
                            : "Keeps this train on your board after departure. Updates while the app is open and stops tracking when arrival is confirmed.")
                    }
                }
                Section {
                    if let stops = service.routeStops, !stops.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                                JourneyStopRow(service: service, stop: stop, index: index, stops: stops)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(20)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 26))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        Text("Calling points unavailable").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Route")
                } footer: {
                    NationalRailAttribution()
                }
                .listSectionMargins(.vertical, 0)

            }
            .contentMargins(.vertical, 8, for: .scrollContent)
            .sheet(isPresented: $showingAutoTracking) {
                if let tracker {
                    AutoTrackingEditor(draft: tracker.autoRules.first { $0.matches(service) }
                        ?? AutoTrackingRule(departure: service), tracker: tracker)
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active,
                      !detailsKey.isEmpty, !detailsKey.contains("$(") else { return }
                while !Task.isCancelled {
                    await refreshLocation()
                    do { try await Task.sleep(for: .seconds(30)) }
                    catch { return }
                }
            }
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
        isLoadingLocation = true
        defer { isLoadingLocation = false }
        do {
            let updated = try await provider.serviceDetails(for: service)
            guard !Task.isCancelled else { return }
            let merged = updated.mergingEarlierStops(from: service)
            detailedDeparture = merged
            tracker?.receive(merged)
            locationError = nil
        } catch {
            guard !Task.isCancelled else { return }
            locationError = detailedDeparture == nil ? "Live location could not be loaded." : "Location update failed · showing last report."
        }
    }

}
