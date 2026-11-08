import SwiftUI

extension ServiceStatus {
    var color: Color {
        switch self {
        case .onTime, .early: .green
        case .delayed(let minutes): minutes > 10 ? .red : .orange
        case .cancelled: .red
        case .unknown: .secondary
        case .disrupted: .orange
        }
    }
}
