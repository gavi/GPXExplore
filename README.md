# GPXExplore

A cross-platform macOS/iOS application for viewing GPX track files on a map with elevation data visualization.

## Features

- Open and parse GPX track files: tracks, routes, waypoints, metadata, and Garmin-style
  extensions (heart rate, cadence, power, speed, temperature)
- Display tracks on an interactive map, coloured by grade or by elevation
- A chart of elevation or any recorded sensor series, with hover/scrub and zoom
- Workout statistics: moving time, pace and speed, gain and loss, splits per km or mile
- Share the GPX file, or export the map and chart as an image
- Finder Quick Look preview on the Mac
- One codebase for iPhone, iPad and Mac

## Getting Started

### Prerequisites

- Xcode 16 or later
- macOS 14.6 or later, iOS 17.6 or later

### Building the Project

Clone the repository and open the Xcode project:

```bash
git clone https://github.com/gavi/GPXExplore.git
cd GPXExplore
open GPXExplore.xcodeproj
```

Build and run the application using Xcode or with the following commands:

```bash
# Build
xcodebuild -project GPXExplore.xcodeproj -scheme GPXExplore build

# Run
xcodebuild -project GPXExplore.xcodeproj -scheme GPXExplore run

# Clean
xcodebuild -project GPXExplore.xcodeproj -scheme GPXExplore clean
```

## Architecture

GPXExplore follows the MVVM (Model-View-ViewModel) architecture pattern with SwiftUI:

- **Models**: Data structures and business logic
  - `SettingsModel`: Manages user preferences
- **Views**: UI components
  - `ContentView`: Main application view
  - `MapView`: Platform-specific map implementation
- **Utils**:
  - `GPXParser`: Handles parsing of GPX files

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.