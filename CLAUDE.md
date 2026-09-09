# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
The product wrapper one level up (`../CLAUDE.md`, `../docs/`) holds the release plan, shipping and
store notes; read it first.

## Build and Test Commands
- Build (Mac): `xcodebuild -project GPXExplore.xcodeproj -scheme GPXExplore -destination 'platform=macOS' build`
- Build (iOS simulator): `xcodebuild -project GPXExplore.xcodeproj -scheme GPXExplore -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' build`
- Run the Mac app on a file: `open -a <built .app> file.gpx` (ad-hoc signing: `CODE_SIGN_IDENTITY="-"`)
- Parser/statistics check without Xcode: compile `GPXExplore/Utils/GPXParser.swift` and
  `GPXExplore/Models/TrackStatistics.swift` with `swiftc -framework CoreLocation` plus a `main.swift`
  and a stub `GPXWorkout`; the 1.5 harness in the session scratchpad did exactly that.
- There is no test target yet (planned).

## App Functionality
- GPX Explore is a cross-platform iOS/iPadOS/macOS viewer for GPX files: tracks coloured by grade or
  elevation, a scrubbable chart of elevation or any recorded sensor series, peaks and valleys, a
  route card with workout statistics and splits, a tracks/waypoints drawer, share and image export.
- `QuickLookGPX` is a Mac Quick Look extension (embedded in the Mac app) with its **own copy** of
  the parser (`QuickLookGPX/GPXParserBridge.swift`) because an app extension cannot link the app
  target. A parser fix must be made in both; the copy skips extensions and full metadata on purpose.

## Architecture (as of 1.5)
- **Model** (`Utils/GPXParser.swift`): `GPXFile` (metadata, creator, version, tracks, waypoints),
  `GPXTrack` (name/type/date, cmt/desc/src/links/number, `isRoute`, extensions, segments),
  `GPXTrackSegment` (`locations: [CLLocation]` + parallel `samples: [SensorSample]`, `hasElevation`,
  `hasTimestamps`), `GPXWaypoint` (full wptType), `SensorSample` (heart rate, cadence, power,
  temperature, speed, plus every other trkpt field and unknown extension leaves).
- **Parser**: one `XMLParser` delegate with an element stack of local names; namespace prefixes
  are ignored; `GPXDate` handles ISO 8601 with/without fractional seconds and zone-less stamps.
  Missing `<ele>` → `verticalAccuracy = -1`; missing `<time>` → `gpxMissingTimestamp` (epoch 0);
  the segment flags say which. Points without valid lat/lon are skipped. Nothing is fabricated.
- **Statistics** (`Models/TrackStatistics.swift`): computed once per change of the visible
  segments and cached in `ContentView` state; distance prefix sums (the chart's x axis), moving
  time (gaps > 30 s or slower than 0.5 m/s excluded), speeds, pace, gain/loss (1 m threshold),
  sensor averages, splits. `StatsFormat` formats pace/speed/duration/elevation/distance.
- **Views**: `ContentView` (state, toolbar, share/export, shortcuts) → `MapView` (MKMapView
  representable per platform; `MapView+Common.swift` has `ElevationPolyline`, the two renderers,
  annotations), `RouteInfoOverlay` (the card), `ElevationOverlay` (chart + `ChartMetric` picker),
  `TracksDrawer`, `SettingsView`. `Models/TrackColors.swift` is the single source of track colours
  and grade computation, used by the renderers, the exporter and (as a copy) Quick Look.
- **Export** (`Export/MapImageExporter.swift`): `MKMapSnapshotter` + CoreGraphics track pass +
  chart bitmap from `ImageRenderer` → PNG in the temp dir; `ExportSheet` shares/saves it.
- **Mac window** (`Window/MacWindowSizer.swift`): first document window fills the screen; the
  frame is then autosaved and restored (`GPXExploreDocumentWindow`).
- Settings are `UserDefaults`-backed in `SettingsModel`; the map renderers also read the
  visualization mode and line width straight from `UserDefaults`.

## Code Style Guidelines
- **Imports**: Group imports by framework (SwiftUI, MapKit, etc.) with Foundation first
- **Formatting**: Use 4-space indentation, avoid trailing whitespace
- **Types**: Use Swift's type inference where appropriate, specify types for public APIs
- **Naming**: Follow Apple's API Design Guidelines (camelCase for properties/methods, TitleCase for types)
- **Error Handling**: Use appropriate error handling with do/catch blocks and meaningful error messaging
- **Comments**: Say why, not what; keep the parser's element rules commented
- **Access Control**: Restrict access to implementation details with private/fileprivate
- **Extensions**: Prefer extensions to organize functionality by purpose
- **Environment Handling**: Use `#if` conditional compilation for platform-specific code
- **Xcode Cloud** builds every push to `main` with an older Xcode than this Mac: keep arithmetic
  explicitly typed and gate anything newer than iOS 17.6 / macOS 14.6 with `#available`.
