# Tom's Trains

Native SwiftUI iPhone app for iOS 26+. Default journeys run from St Neots to King's Cross / St Pancras from 02:00 until noon, then reverse. Routes, swap times and appearance are configurable. The reverse button overrides the direction until the next scheduled transition.

## API setup

Live data comes directly from National Rail's [Darwin feeds](https://www.nationalrail.co.uk/developers/darwin-data-feeds/). Create a [Rail Data Marketplace](https://raildata.org.uk/) account, subscribe to the three products below, and get the **consumer key** for each subscription.

| Marketplace subscription | What the app uses it for | Configuration key |
| --- | --- | --- |
| [Live Departure Board – Staff Version](https://raildata.org.uk/dataProduct/P-53613c24-0205-4d3b-919a-b338858e130e/overview) | `GetDepBoardWithDetails`: upcoming and earlier trains, platforms, cancellations, and the service ID used for tracking. | `NATIONAL_RAIL_BOARD_API_KEY` |
| [Query Services and Service Details](https://raildata.org.uk/dataProduct/P-9a4b5235-d06a-483d-b12f-7d0d95b06b18/overview) | `GetServiceDetailsByRID`: full journey stops and updates for tracked trains. | `NATIONAL_RAIL_QUERY_SERVICES_API_KEY` |
| [Reference Data](https://raildata.org.uk/dataProduct/P-c73f0d2a-c233-497d-846b-8354e2cac326/overview) | `GetStationList/0` and `GetReasonCodeList`: station names and delay or cancellation descriptions. | `NATIONAL_RAIL_REFERENCE_API_KEY` |

From the project root, copy the example file and fill in the three values in `Configuration/API.xcconfig`:

```sh
cp -n Configuration/API.example.xcconfig Configuration/API.xcconfig
```

Use the consumer keys, which the app sends in the `x-apikey` request header. The public version of Live Departure Board and the separate Knowledgebase Stations feed are not required. See the [API audit](API-Audit.md) for endpoint details.

`Configuration/API.xcconfig` is ignored by Git. Xcode embeds these keys in the built app, so keep builds that contain your keys private too. There is no backend to configure. The core test suite uses fixtures and does not require credentials.

## Run in Xcode

1. Install Xcode with the iOS 26 SDK or newer.
2. Open `TomsTrains.xcodeproj` and select the **TomsTrains** scheme.
3. Select an iPhone simulator or a device running iOS 26 or later, then choose **Run**. For a physical device, select your own development team under **Signing & Capabilities**. If the bundle identifier is unavailable to your team, override `PRODUCT_BUNDLE_IDENTIFIER` in the ignored `Configuration/Local.xcconfig`.

If live requests are rejected, check that each subscription is active and its consumer key is in the matching setting. Rebuild after editing the configuration.

## Train information

Darwin station boards include previous and subsequent locations, actual and forecast times, platforms, cancellations and persistent RIDs. Full journey details use `GetServiceDetailsByRID`. The app respects hidden-platform and suppressed-service flags, omits operational passing points, and retains cancelled passenger stops. Actual reports are distinguished from forecasts and NoLog values. Timestamps without an offset are interpreted in Europe/London.

Upcoming services sort by destination arrival. Multiple selected destinations produce one row per train at a boarding station, using the earliest selected arrival. Up to four station-pair requests run concurrently. Failed station requests fail the combined refresh rather than silently omitting that station; stale boards expire after five minutes.

The upcoming feed shows the next eight trains, combined across all selected starting stations and sorted by destination arrival. It searches successive two-hour API windows across midnight until the visible page is filled and the search covers its latest arrival, so later faster trains are considered. The search stops at the next configured overnight reset (02:00 by default) even if fewer than eight remain. The selected direction stays the same throughout that search.

**See earlier** reveals eight more services at a time, requesting older two-hour windows as needed until the configured start of the current travel day (02:00 by default), including the previous calendar evening after midnight. Previously loaded rows stay chronological in the same feed. The API can omit services it no longer retains; this is not a complete archive or a promise of previous-day history. Earlier rows show their actual departure time, lateness and public platform when supplied.

**Track train** persists a journey locally and refreshes it while the app is active. Tracking ends on an actual destination arrival or an actual report at a later stop, unless the destination was cancelled. A confirmed service completion also ends tracking, including after a cancelled destination. It does not end merely because an ETA elapsed. Old saved board IDs are migrated by matching origin, scheduled departure, destination and operator to a unique RID. A missing or ambiguous match stays tracked with an update error.

The foreground refresh loop updates the main feed and tracked journeys. An open detail sheet also refreshes every 30 seconds. A shared 20-second cache coalesces overlapping service-detail requests. There is no per-station platform enrichment, arrival-board fallback, backend, notification delivery, widget or Live Activity.

Reference Data supplies the station picker and the delay or cancellation descriptions beneath each service status. Successful lookups are cached for 24 hours. A reason lookup failure does not block live train details. Full station names determine shared destination headings.

## Validation

Run core tests with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The same test source is included in the Xcode scheme. Live integration verification and its limits are recorded in [API-Audit.md](API-Audit.md). A simulator build does not replace a fresh physical-device check after installing the new build.

Once all remaining services before the overnight reset are visible, **See tomorrow’s services** loads up to eight departures for the next travel day on the currently selected route. They appear below tonight’s trains under a separate label and refresh while visible. Changing route or crossing the overnight reset clears that preview.

Multiple trains can be tracked independently. From each tracked train’s details, **Configure auto-tracking** saves its route and UK-local scheduled time, with Monday–Friday selected initially. Settings lists all schedules; each can be edited, paused, or removed independently. Automatic lookup runs on app opening and foreground refreshes, independently of the visible board direction, and requires an exact route/time match. A manual stop suppresses that train’s occurrence for the day across app restarts. Each train stops tracking on confirmed destination arrival. No background activation, notifications or Live Activities are delivered.

**See later** expands the current travel-day feed by eight trains per tap, retaining previous rows and destination-arrival sorting. The expanded count persists during foreground refreshes and resets when the route changes. Tomorrow’s preview has its own See later button. Once the current day is exhausted, the tomorrow button becomes available instead.

## Source organisation

- `Shared/Models`: stations, departures, route stops and tracking values.
- `Shared/Board`: observable board controller and history pagination.
- `Shared/Tracking`: multiple-train tracking, recurring schedules and UserDefaults persistence.
- `Shared/Services`: rail operations and station directory; Darwin response mapping is isolated in `Services/Darwin`.
- `Shared/Networking`: authentication, HTTP errors and request coalescing.
- `Shared/Settings` and `Shared/Time`: route configuration and London calendar/time handling.
- `TomsTrains/Board`, `Details`, `Settings`, `Style`: focused SwiftUI screens and components.
- `TomsTrainsTests`: separate suites for domain logic, providers, board pagination, tracking and settings.

`DepartureProviding` covers upcoming/history/detail/automatic queries. Board tests inject this interface and a clock; tracker and detail consumers also accept an injected provider. `TrackingStore` preserves existing on-device storage keys. Both the Swift package and Xcode targets include the shared code and tests. The project generator discovers Swift files recursively, but should only be used for a new project: it replaces local project settings. Keep the existing Xcode project for normal development.
