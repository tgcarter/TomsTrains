# Current subscription audit — 27 September 2026

Verified against production request URLs, Info.plist bindings and local configuration key names. Exactly three Marketplace subscriptions remain in use:

- **Reference Data**: `GetStationList/0` and `GetReasonCodeList` for station selection and delay/cancellation descriptions.
- **Live Departure Board - Staff Version**: `GetDepBoardWithDetails/{crs}/{time}` for current, earlier, later and next-day feeds, and recurring tracking lookup.
- **Query Services and Service Details**: `GetServiceDetailsByRID/{rid}` for full routes and tracked-service updates.

The following subscriptions shown in Marketplace are unused by this app and may be cancelled if no other application needs them:

- Live Arrival and Departure Boards
- NationalRail Knowledgebase Stations (JSON) - Prod
- Service Details
- Live Departure Board (the public product, not Staff Version)

No subscriptions were cancelled automatically. No new live API probes were made for this audit. Production demo provider, mode flags and UI have been removed. Deterministic timetable fixtures are test-target-only and are not included in the app.

---

# Rail API audit — 22 September 2026

## Active subscriptions after migration

| Product | App use | Operations |
| --- | --- | --- |
| [Live Departure Board – Staff Version](https://raildata.org.uk/dashboard/dataProduct/P-53613c24-0205-4d3b-919a-b338858e130e/specification) | Upcoming and earlier departures, route stops, actual times, public platforms, RIDs | `GetDepBoardWithDetails/{crs}/{time}` |
| [Query Services and Service Details](https://raildata.org.uk/dashboard/dataProduct/P-9a4b5235-d06a-483d-b12f-7d0d95b06b18/specification) | Full journey details and tracking after departure | `GetServiceDetailsByRID/{rid}` |
| [Reference Data](https://raildata.org.uk/dataProduct/P-c73f0d2a-c233-497d-846b-8354e2cac326/overview) | Station picker and delay/cancellation descriptions | `GetStationList/0`, `GetReasonCodeList` |

All requests remain on Rail Data Marketplace. `QueryServices` was used during investigation; the app does not call it because the station board already supplies the RID. Reference Data is now required for reason descriptions and the station directory.

## Removed overlap

The old public Live Departure Board, public Service Details, and combined Live Arrival and Departure Boards are no longer used. Their consumer-key bindings and local key entries have been removed. They can be unsubscribed in Marketplace; the app does not cancel external subscriptions itself.

Removed the expired public-service-ID recovery path, destination-arrivals matching, destination-side public-details lookup, per-station platform requests and their cache. Replaced two foreground tracking loops with one. Overlapping detail requests use one credential-scoped 20-second cache with in-flight request sharing. The station directory remains necessary and independent.

## Live verification

Using the new credentials and the actual Swift provider:

- SNO → KGX: three upcoming services; valid empty recent-history result at test time.
- SNO → STP: one upcoming and four earlier services; all four earlier trains had a public platform and actual departure report.
- KGX → SNO: valid empty upcoming and recent-history results at test time.
- STP → SNO: four upcoming and four earlier services; all four earlier trains had a public platform and actual departure report.
- An additional older STP → SNO window returned four services.
- Full RID details for completed journeys decoded correctly, including all passenger stops and automatic tracking completion.
- Raw requests confirmed `filterCrs=SNO` includes intermediate stops, not just final destinations. `numRows=150` was accepted.
- A completed 20:16 St Pancras service returned platform B, actual departure 20:18:52, and St Neots platform 1 / actual arrival 21:12:50.

Some previous-day records remained queryable, but previous-date queries also returned null or sparse results. Previous-day completeness and long-term retention are not established. The app deliberately pages only today's available data. Unannounced platforms stay hidden on upcoming calls. For confirmed actual calls, the decoder displays the platform supplied in that report as historical information, even when it is now hidden from the live station display. It does not recover a missing platform from an older cached value.

No backend, Darwin Push Port, push notifications or Live Activities were introduced. Physical-device visual QA remains separate from automated tests, simulator build and live API verification.

## Automated and app checks

- 52 core tests passed after replacing the obsolete public-API fixtures with Darwin contract tests. Coverage includes actual versus forecast reports, cancellations, hidden platforms, saved-ID migration, older windows, truncated boards, request coalescing and route deduplication.
- iOS Simulator build succeeded. The built app contains only the three current National Rail key bindings, all populated.
- Installed and launched the migrated app in the iPhone 17 Pro simulator. The live board rendered departure times, destination ETAs, platforms and operator logos without a startup error.

## Combined-feed follow-up verification

- Completed, suppressed KGX services with confirmed actual departures now remain in earlier history. A live historical sample contained KGX 17:12, 17:42 and 18:12 mixed chronologically with STP trains. Upcoming hidden platforms remain hidden; confirmed historical calls now show the supplied platform used.
- A two-hour upcoming lookup was insufficient late at night. Upcoming searches now query successive two-hour windows for all selected station pairs until at least eight distinct services are available, bounded to the next overnight reset (02:00 by default). The displayed board defaults to eight, sorted by destination arrival; it keeps the selected route across midnight.
- The live Swift provider returned eight mixed services, including STP 00:46 arriving SNO 01:57 and KGX 01:36 arriving SNO 02:40 on 23 September. The earlier empty KGX result only described the original two-hour window, not the rest of the night.
- All 56 core tests pass, including midnight pagination, the eight-train display limit, both-origin merging, completed suppressed services and bounded empty searches.

The history page size is now eight, matching the upcoming feed. Journey graphics follow confirmed progress along the full route, including beyond the selected destination, and switch the line and completed markers to neutral grey on arrival at the final stop. Auto-untracking at the selected destination is unchanged.

The overnight reset now also caps upcoming departures by their scheduled boarding time. Darwin sdd is a schedule date, not the app travel-day boundary: the verified 01:36 KGX service has sdd 23 September. Trains scheduled before reset remain eligible even if delayed past it; arrivals after reset are allowed. The board can show fewer than eight rather than fill with next-day morning services.

Auto-tracking reuses `GetDepBoardWithDetails` for a one-minute window at the recurring departure time, with origin and destination filters. No additional API subscription is used. Matching requires the exact UK-local scheduled boarding date/time; missing or ambiguous matches are left untracked. Checks only run while the app is active and an existing manually tracked train has priority over recurring rules. Missing matches retry at most once per minute; handled daily occurrences persist locally.

## Review fixes and organisation — 23 September 2026

All five review findings are covered: searches include later departure windows until the displayed page’s latest arrival is covered; confirmed full-service completion frees the tracking slot even after a cancelled destination; history uses the configurable travel-day start; operational boarding calls are rejected; custom origins retain their supplied station names.

Models, board state, persistence, rail operations, Darwin mapping, HTTP/cache and SwiftUI components now live in dedicated files and folders. Rail operations and the controller clock are injectable. There are 76 passing tests, including direct board pagination/overnight tests. The existing Xcode app builds with no errors or warnings, and all XCBuildConfiguration objects were verified unchanged during the source-membership update. No new subscriptions or endpoints were introduced.

## Service-specific reasons — 26 September 2026

The Darwin JSON schema supplies `delayReason` / `cancelReason` as numeric `ReasonCodeWithLocation.Value` objects. These are now retained separately from display text; descriptions, when supplied as text, appear directly below the train status. Numeric codes are never presented as guessed descriptions.

Live probes of `GetReasonCodeList` through both existing board/details product bases and `GetReasonCode/832` through the details base all returned HTTP 403. No unsupported lookup has been added to normal app refreshes. Official reason-description access remains required before code-only responses can be shown as meaningful explanations. No new subscription or credentials were added.

## Reference Data integration — 26 September 2026

[Reference Data](https://raildata.org.uk/dashboard/dataProduct/P-c73f0d2a-c233-497d-846b-8354e2cac326/specification) is now configured with its own consumer key from the subscribed Marketplace session. Service details use `/LDBSVWS/api/ref/20211101/GetReasonCodeList` to resolve delay/cancellation codes; successful responses are cached in memory for 24 hours and shared across trains. Lookup failures preserve fresh live service details.

Overlap audit:
- Keep Live Departure Board: upcoming, earlier and paginated board services.
- Keep Query Services and Service Details: complete individual service reports after departure.
- Reference Data also exposes `GetStationList/{currentVersion}` with `crs` and `Value` names, sufficient in schema for the station picker. It is a potential replacement for Knowledgebase Stations, not for either live-service API.
- Retain Knowledgebase Stations until Reference Data station coverage is live-verified. Current probes of the new reason list, `GetStationList/0`, and the existing Knowledgebase station feed all returned a generic HTML HTTP 403, so this result does not isolate a subscription-permission problem.

No station endpoint or external subscription has been removed yet. Fixture tests cover reason text, unknown codes, lookup failures, and the official reference station response shape; these are not evidence of live availability.

### Completed native verification and cleanup

Using Foundation URLSession, the same transport as the app, all three reference/old-station probes returned HTTP 200. The earlier generic HTML 403 results were specific to the shell request path and did not establish missing subscription access.

Reference Data returned 416 reason records and 2,930 unique CRS codes. Knowledgebase returned 2,613 codes; 2,609 overlap. The four omitted codes are Kidderminster (S.V.R), St Pancras Eurostar, Ryde Hoverport and White Rose (still under construction per Northern/WYCA). Reference Data contains 321 additional codes. SNO, KGX and domestic STP names were verified. This list matches the domestic Darwin board use case; it is not an identical facilities/location directory.

The station picker now exclusively uses Reference Data, with a new cache key and no cache migration. Knowledgebase station HTTP/decoding code and credential bindings were removed. Its Marketplace subscription can be cancelled manually; no subscription was cancelled by the app. Live departure boards and RID details remain necessary and have no functional replacement in Reference Data.
