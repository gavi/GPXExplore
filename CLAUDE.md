# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
The product wrapper one level up (`../CLAUDE.md`, `../docs/`) holds the release plan, shipping and
store notes; read it first.

## Build and Test Commands
- Build (Mac): `xcodebuild -project GPXExplore.xcodeproj -scheme GPXExplore -destination 'platform=macOS' build`
- Build (iOS simulator): `xcodebuild -project GPXExplore.xcodeproj -scheme GPXExplore -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' build`
- Run the Mac app on a file: `open -a <built .app> file.gpx` (ad-hoc signing: `CODE_SIGN_IDENTITY="-"`)
- Parser/statistics check without Xcode: `../tools/gpxcheck/run.sh ../samples/public/*.gpx`
  compiles `Utils/GPXParser.swift` and `Models/TrackStatistics.swift` with a small `main.swift`
  and prints one block per file (points, flags, times, elevation, sensors, splits, parse time).
  `../samples/README.md` says what each file exercises and lists the expected numbers. Run it
  after any change to those two files.
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
  are ignored; `GPXDate.fast` reads ISO 8601 (fraction, Z, ±HH:MM, zone-less = UTC) with integer
  maths and falls back to the formatters, which cost ~60 µs a call and made big files take a
  second. Missing `<ele>` → `verticalAccuracy = -1` (so does the 9999 sentinel); missing `<time>`
  → `gpxMissingTimestamp` (epoch 0); segment flags say whether *any* point had them, validity is
  per point. Route points are never timed (their `<time>` is a creation stamp). Points without
  valid lat/lon are skipped. Nothing is fabricated.
- **Statistics** (`Models/TrackStatistics.swift`): computed once per change of the visible
  segments and cached in `ContentView` state. Distance prefix sums (the chart's x axis); a
  timed interval needs valid stamps at both ends, same segment, clock moving forward; a stop is
  slower than 0.5 m/s over a window of at least 5 s (`speeds` holds that windowed speed per
  point, the chart uses it too; max speed is a median of five of them); average speed/pace =
  timed distance over moving time; elapsed
  skips gaps over a day; gain/loss accumulate with 1.5 m hysteresis; cadence ignores zeros;
  splits. Every rule has a file in `../samples` behind it. `StatsFormat` formats
  pace/speed/duration/elevation/distance.
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
- **Document type** (`GPXExplore/Info.plist`): exports `com.topografix.gpx` and claims it as
  Owner with `GPXDocumentIcon.icns` (a loose resource; source art in `Design/`, rebuild with
  `iconutil -c icns Design/GPXDocumentIcon.iconset`). Do not put an `.iconset` in the asset
  catalog (it is ignored) and do not claim `public.xml`.

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
