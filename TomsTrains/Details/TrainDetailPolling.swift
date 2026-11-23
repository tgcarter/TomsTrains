import SwiftUI

extension View {
    func pollingTrainDetails(when enabled: Bool, refresh: @escaping @MainActor () async -> Void) -> some View {
        modifier(TrainDetailPolling(enabled: enabled, refresh: refresh))
    }
}

private struct TrainDetailPolling: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let enabled: Bool
    let refresh: @MainActor () async -> Void

    func body(content: Content) -> some View {
        let isActive = enabled && scenePhase == .active
        content.task(id: isActive) {
            guard isActive else { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
    }
}
