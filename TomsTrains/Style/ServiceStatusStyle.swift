import SwiftUI

struct CompactStatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon.accessibilityHidden(true)
            configuration.title
        }
    }
}

extension ServiceStatus {
    var color: Color {
        switch self {
        case .onTime, .early: .green
        case .delayed(let minutes): minutes > 10 ? .red : .orange
        case .delayedWithoutEstimate: .orange
        case .cancelled: .red
        case .unknown: .secondary
        case .disrupted: .orange
        }
    }
}
