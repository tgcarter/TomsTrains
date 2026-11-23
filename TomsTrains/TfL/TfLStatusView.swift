import SwiftUI

struct TfLStatusView: View {
    let isVisible: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var lines: [TfLLine] = []
    @State private var updatedAt: Date?
    @State private var failed = false
    @State private var requestID: UUID?
    @State private var isRefreshingManually = false

    var body: some View {
        NavigationStack {
            List {
                DepartureBoardHeader(title: "TfL", trailingSpace: 64)
                if failed {
                    if updatedAt == nil {
                        ContentUnavailableView {
                            Label("TfL Status Unavailable", systemImage: "wifi.exclamationmark")
                        } actions: {
                            Button("Try Again") { Task { await refresh() } }
                        }
                    } else {
                        Label("Couldn’t refresh. Showing the last update.", systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if updatedAt == nil {
                    ProgressView("Loading TfL status…")
                }

                let disrupted = lines.filter(\.isDisrupted)
                let otherLines = lines.filter { !$0.isDisrupted }
                if !disrupted.isEmpty {
                    Section {
                        ForEach(disrupted) { line in lineRow(line) }
                    } header: {
                        Text("Disruptions")
                    } footer: {
                        if otherLines.isEmpty { statusFooter }
                    }
                }
                if !otherLines.isEmpty {
                    Section {
                        ForEach(otherLines) { line in lineRow(line) }
                    } header: {
                        Text(disrupted.isEmpty ? "Lines" : "Other Lines")
                    } footer: {
                        statusFooter
                    }
                } else if lines.isEmpty && updatedAt != nil {
                    Section {
                        ContentUnavailableView("No Line Status Available", systemImage: "tram")
                    } footer: {
                        statusFooter
                    }
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .overlay(alignment: .topTrailing) {
                DepartureBoardControls(isLoading: isRefreshingManually,
                    refresh: { Task { await refreshManually() } })
                    .padding(.trailing, 20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await refreshManually() }
            .task(id: isVisible && scenePhase == .active) {
                guard isVisible, scenePhase == .active else { return }
                while !Task.isCancelled {
                    await refresh()
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch { return }
                }
            }
        }
    }

    private var statusFooter: some View {
        BoardFooter(updatedAt: updatedAt, branding: .tfl)
    }

    @ViewBuilder private func lineRow(_ line: TfLLine) -> some View {
        if line.reasons.isEmpty {
            lineLabel(line)
        } else {
            DisclosureGroup {
                ForEach(line.reasons, id: \.self) { reason in
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } label: {
                lineLabel(line)
            }
        }
    }

    private func lineLabel(_ line: TfLLine) -> some View {
        HStack(alignment: .center, spacing: 12) {
            TfLLineBadge(line: line)
            VStack(alignment: .leading, spacing: 4) {
                Text(line.name).font(.headline)
                if line.lineStatuses.isEmpty {
                    Text("Status unavailable").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(line.orderedStatuses.enumerated()), id: \.offset) { _, status in
                        Label(status.statusSeverityDescription,
                            systemImage: status.isDisrupted ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .labelStyle(CompactStatusLabelStyle())
                            .font(.footnote.weight(status.isDisrupted ? .semibold : .regular))
                            .foregroundStyle(status.isDisrupted ? Color.orange : Color.green)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func refresh() async {
        let id = UUID()
        requestID = id
        do {
            let updated = try await TfLStatusProvider().lines()
            guard !Task.isCancelled, requestID == id else { return }
            lines = updated
            updatedAt = Date()
            failed = false
        } catch {
            guard !Task.isCancelled, requestID == id else { return }
            failed = true
        }
    }

    private func refreshManually() async {
        guard !isRefreshingManually else { return }
        isRefreshingManually = true
        defer { isRefreshingManually = false }
        await refresh()
    }
}

private struct TfLLineBadge: View {
    let line: TfLLine
    @ScaledMetric(relativeTo: .body) private var size = 36.0

    // RGB values from TfL's colour standard for Tube, Overground and the other modes.
    private static let lineColours: [String: UInt32] = [
        "bakerloo": 0xB26300, "central": 0xDC241F, "circle": 0xFFC80A, "district": 0x007D32,
        "hammersmith-city": 0xF589A6, "jubilee": 0x838D93, "metropolitan": 0x9B0058,
        "northern": 0x000000, "piccadilly": 0x0019A8, "victoria": 0x039BE5, "waterloo-city": 0x76D0BD,
        "liberty": 0x5D6061, "lioness": 0xFAA61A, "mildmay": 0x0077AD,
        "suffragette": 0x5BBD72, "weaver": 0x823A62, "windrush": 0xED1B00,
        "dlr": 0x00AFAD, "elizabeth": 0x60399E, "tram": 0x5FB526
    ]

    private var hex: UInt32 {
        Self.lineColours[line.id] ?? Self.lineColours[line.id.replacingOccurrences(of: "-line", with: "")] ?? 0x0019A8
    }

    var body: some View {
        let red = Double((hex >> 16) & 255) / 255
        let green = Double((hex >> 8) & 255) / 255
        let blue = Double(hex & 255) / 255
        let colour = Color(red: red, green: green, blue: blue)
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        Image(systemName: line.modeName == "tube" ? "tram.tunnel.fill" : "tram.fill")
            .font(.system(size: size * 0.47, weight: .semibold))
            .foregroundStyle(luminance > 0.179 ? Color.black : Color.white)
            .frame(width: size, height: size)
            .background(colour, in: RoundedRectangle(cornerRadius: size * 0.26))
            .overlay { RoundedRectangle(cornerRadius: size * 0.26).strokeBorder(.primary.opacity(0.12)) }
            .accessibilityHidden(true)
    }

    private func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}
