# GPXViewer

A cross-platform macOS/iOS application for viewing GPX track files on a map with elevation data visualization.

## Features

- Open and parse GPX track files
- Display tracks on an interactive map
- Gradient-colored tracks based on elevation changes
- Display track statistics
- Support for both macOS and iOS platforms

## Getting Started

### Prerequisites

- Xcode 14.0 or later
- macOS Ventura or later (for development)
- iOS 16.0 or later (for iOS deployment)

### Building the Project

Clone the repository and open the Xcode project:

```bash
git clone <repository-url>
cd GPXViewer
open GPXViewer.xcodeproj
```

Build and run the application using Xcode or with the following commands:

```bash
# Build
xcodebuild -project GPXViewer.xcodeproj -scheme GPXViewer build

# Run
xcodebuild -project GPXViewer.xcodeproj -scheme GPXViewer run

# Clean
xcodebuild -project GPXViewer.xcodeproj -scheme GPXViewer clean
```

## Architecture

GPXViewer follows the MVVM (Model-View-ViewModel) architecture pattern with SwiftUI:

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