import SwiftUI

@main
struct TomsTrainsApp: App {
    var body: some Scene {
        WindowGroup { MainTabs() }
    }
}

private struct MainTabs: View {
    private enum Page { case commute, live, plan, tfl, settings }

    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = Page.commute
    @State private var settings = RouteSettings.load()
    @State private var tracker = TrainTracker()

    var body: some View {
        TabView(selection: $selection) {
            Tab("Commute", systemImage: "tram.fill", value: Page.commute) {
                DepartureBoardView(settings: $settings, tracker: tracker, isVisible: selection == .commute)
            }
            Tab("Live", systemImage: "list.bullet.rectangle", value: Page.live) {
                LiveStationBoardView(isVisible: selection == .live)
            }
            Tab("Plan", systemImage: "map", value: Page.plan) {
                JourneyPlannerView()
            }
            Tab("TfL", systemImage: "tram.tunnel.fill", value: Page.tfl) {
                TfLStatusView(isVisible: selection == .tfl)
            }
            Tab("Settings", systemImage: "gearshape", value: Page.settings) {
                SettingsView(settings: $settings, tracker: tracker)
            }
        }
        .tint(.blue)
        .preferredColorScheme(settings.appearance.colorScheme)
        .onChange(of: settings) { _, updated in
            updated.save()
            tracker.pruneExpired(settings: updated)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                tracker.pruneExpired(settings: settings)
                await tracker.refresh()
                await tracker.autoTrack(at: Date())
                let secondsUntilReset = settings.travelDayEnd(after: Date()).timeIntervalSinceNow
                do { try await Task.sleep(for: .seconds(max(0.1, min(30, secondsUntilReset)))) }
                catch { return }
            }
        }
    }
}
