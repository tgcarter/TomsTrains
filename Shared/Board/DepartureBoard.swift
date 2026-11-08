import Foundation
import Observation

@MainActor @Observable
final class DepartureBoard {
    private let provider: (any DepartureProviding)?
    private let clock: @Sendable () -> Date
    private var railProvider: any DepartureProviding { provider ?? NationalRailProvider(settings: settings) }
    private var travelDayStart: Date?
    private var refreshID = UUID()
    var settings = RouteSettings.load()
    var snapshot: DepartureSnapshot?
    var errorMessage: String?
    var now: Date
    var isLoading = false
    var earlier: [Departure] = []
    private var earlierPagination = EarlierDeparturePagination()
    private var earlierCursor: Date?
    private var moreHistoryAvailable = true
    var visibleEarlier: [Departure] { earlierPagination.visible(in: earlier) }
    var canLoadEarlier: Bool { !hasLoadedEarlier || earlierError != nil || earlierPagination.hasMore(in: earlier) || moreHistoryAvailable }
    var earlierError: String?
    var isLoadingEarlier = false
    var hasLoadedEarlier = false
    private var recentServices: [Departure] = []
    private var recentRouteKey: String?
    private var earlierRequestID = UUID()
    var tomorrowSnapshot: DepartureSnapshot?
    var tomorrowError: String?
    var isLoadingTomorrow = false
    var showsTomorrow = false
    private var upcomingLimit = Departure.defaultBoardLimit
    private var tomorrowLimit = Departure.defaultBoardLimit
    private var tomorrowBoundary: Date?
    private var tomorrowRequestID = UUID()

    var canShowTomorrow: Bool {
        !showsTomorrow && !isLoading && errorMessage == nil
            && snapshot?.isFresh(at: now, settings: settings) == true
            && !canLoadLater
    }

    var canLoadLater: Bool {
        guard let snapshot, snapshot.isFresh(at: now, settings: settings) else { return false }
        return snapshot.hasLaterDepartures == true
            || Departure.board(from: snapshot.departures, at: now, limit: Int.max,
                selection: settings.selection(at: now)).count > upcomingLimit
    }

    var canLoadLaterTomorrow: Bool {
        guard let tomorrowSnapshot, tomorrowSnapshot.isFresh(at: now, settings: settings) else { return false }
        return tomorrowSnapshot.hasLaterDepartures == true
            || tomorrowSnapshot.departures.count > tomorrowLimit
    }

    func loadLater() async {
        guard !isLoading else { return }
        upcomingLimit += Departure.defaultBoardLimit
        await refresh()
    }

    func loadLaterTomorrow() async {
        guard !isLoadingTomorrow else { return }
        tomorrowLimit += Departure.defaultBoardLimit
        await loadTomorrow()
    }

    var tomorrowDepartures: [Departure] {
        guard let tomorrowSnapshot, tomorrowSnapshot.isFresh(at: now, settings: settings) else { return [] }
        return Departure.board(from: tomorrowSnapshot.departures, at: now, limit: tomorrowLimit, selection: settings.selection(at: now))
    }

    func loadTomorrow() async {
        guard !isLoadingTomorrow else { return }
        let id = UUID()
        tomorrowRequestID = id
        let requestedAt = clock()
        let selection = settings.selection(at: requestedAt)
        let boundary = settings.travelDayEnd(after: requestedAt)
        isLoadingTomorrow = true
        tomorrowError = nil
        defer { if tomorrowRequestID == id { isLoadingTomorrow = false } }
        do {
            let loaded = try await railProvider.snapshot(at: requestedAt, tomorrow: true, limit: tomorrowLimit)
            guard !Task.isCancelled, tomorrowRequestID == id,
                  settings.selection(at: clock()).key == selection.key,
                  settings.travelDayEnd(after: clock()) == boundary else { return }
            guard loaded.isFresh(at: clock(), settings: settings) else { throw RailAPIError.unavailable }
            tomorrowSnapshot = loaded
            tomorrowBoundary = boundary
            showsTomorrow = true
        } catch {
            guard !Task.isCancelled, tomorrowRequestID == id else { return }
            tomorrowError = "Tomorrow’s services couldn’t be loaded. Tap to try again."
        }
    }

    private func resetTomorrow() {
        tomorrowRequestID = UUID()
        tomorrowSnapshot = nil
        tomorrowError = nil
        tomorrowBoundary = nil
        showsTomorrow = false
        tomorrowLimit = Departure.defaultBoardLimit
        isLoadingTomorrow = false
    }


    func resetEarlier() {
        upcomingLimit = Departure.defaultBoardLimit
        earlierRequestID = UUID()
        earlier = []
        earlierPagination = EarlierDeparturePagination()
        earlierCursor = nil
        moreHistoryAvailable = true
        recentServices = []
        recentRouteKey = nil
        earlierError = nil
        hasLoadedEarlier = false
        isLoadingEarlier = false
    }

    func loadEarlier(revealMore: Bool = true) async {
        guard !isLoadingEarlier else { return }
        let targetCount = earlierPagination.visibleCount + Departure.defaultBoardLimit
        if revealMore, earlierError == nil,
           earlier.count >= targetCount || (!moreHistoryAvailable && earlierPagination.hasMore(in: earlier)) {
            earlierPagination.revealMore()
            return
        }
        let id = UUID()
        earlierRequestID = id
        let requestedAt = clock()
        let selection = settings.selection(at: requestedAt)
        var before = revealMore ? (earlierCursor ?? requestedAt) : requestedAt
        isLoadingEarlier = true
        earlierError = nil
        defer { if earlierRequestID == id { isLoadingEarlier = false } }
        do {
            repeat {
                let start = NationalRailProvider.historyStart(before: before, now: requestedAt, settings: settings)
                let loaded = try await railProvider.earlierDepartures(at: requestedAt, before: before)
                guard !Task.isCancelled, earlierRequestID == id,
                      settings.selection(at: clock()).key == selection.key else { return }
                let retained = earlier + recentServices
                let updated = loaded.map { service in
                    service.retainingHistoricalReport(from: retained.first { $0.id == service.id })
                }
                earlier = Departure.earlier(from: updated + retained, at: clock(), selection: selection, since: settings.travelDayStart(at: clock()))
                if revealMore {
                    earlierCursor = start
                    moreHistoryAvailable = start > settings.travelDayStart(at: requestedAt)
                }
                before = start
            } while revealMore && earlier.count < targetCount && moreHistoryAvailable
            if revealMore { earlierPagination.revealMore() }
            hasLoadedEarlier = true
        } catch {
            guard !Task.isCancelled, earlierRequestID == id else { return }
            earlier = Departure.earlier(from: earlier + recentServices, at: clock(), selection: selection, since: settings.travelDayStart(at: clock()))
            if !hasLoadedEarlier { earlierPagination.revealMore() }
            hasLoadedEarlier = true
            earlierError = "Earlier services couldn’t be updated. Showing any trains already seen in this session."
        }
    }

    var showsInitialLoading: Bool {
        (snapshot == nil && errorMessage == nil) || (departures.isEmpty && isLoading)
    }

    init(provider: (any DepartureProviding)? = nil,
         settings: RouteSettings = RouteSettings.load(),
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.settings = settings
        self.clock = clock
        now = clock()
    }

    var departures: [Departure] {
        guard let snapshot, snapshot.isFresh(at: now, settings: settings) else { return [] }
        return Departure.board(from: snapshot.departures, at: now, limit: upcomingLimit, selection: settings.selection(at: now))
    }

    func refresh(settings: RouteSettings? = nil, resetPagination: Bool = false) async {
        if resetPagination {
            resetEarlier()
            resetTomorrow()
        }
        if let settings { self.settings = settings }
        let requestID = UUID()
        refreshID = requestID
        isLoading = true
        defer { if refreshID == requestID { isLoading = false } }
        now = clock()
        let selection = self.settings.selection(at: now)
        let dayStart = self.settings.travelDayStart(at: now)
        if recentRouteKey != selection.key || travelDayStart != dayStart {
            resetEarlier()
            resetTomorrow()
            recentRouteKey = selection.key
            travelDayStart = dayStart
        }
        if let tomorrowBoundary, tomorrowBoundary != self.settings.travelDayEnd(after: now) { resetTomorrow() }
        do {
            let fresh = try await railProvider.snapshot(at: now, tomorrow: false, limit: upcomingLimit)
            guard refreshID == requestID, !Task.isCancelled else { return }
            snapshot = fresh
            var seen = Set<String>()
            recentServices = (fresh.departures + recentServices).filter {
                $0.scheduled >= now.addingTimeInterval(-7200) && seen.insert($0.id).inserted
            }
            if hasLoadedEarlier {
                let updated = earlier.map { service in
                    service.retainingHistoricalReport(from: recentServices.first { $0.id == service.id })
                }
                earlier = Departure.earlier(from: updated + recentServices, at: now, selection: selection, since: self.settings.travelDayStart(at: now))
            }
            errorMessage = snapshot?.isFresh(at: now, settings: self.settings) == true ? nil : "National Rail’s latest board is out of date. Pull down to try again."
        } catch {
            guard refreshID == requestID, !Task.isCancelled else { return }
            errorMessage = (error as? RailAPIError)?.errorDescription ?? "Departures couldn’t be updated. Pull down to try again."
        }
        if showsTomorrow, refreshID == requestID, !Task.isCancelled { await loadTomorrow() }
        if hasLoadedEarlier, refreshID == requestID, !Task.isCancelled { await loadEarlier(revealMore: false) }
    }
}
