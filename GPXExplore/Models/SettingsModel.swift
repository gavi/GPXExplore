import Foundation
import SwiftUI
import MapKit
import CoreLocation

// Custom model to replace HKWorkout
struct GPXWorkout {
    let activityType: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let totalDistance: Double // in meters
    let metadata: [String: Any]
}

enum MapStyle: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case satellite = "Satellite"
    case hybrid = "Hybrid"

    var id: String { self.rawValue }

    var iconName: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "globe"
        case .hybrid: return "map.fill"
        }
    }

    #if swift(>=5.7) && canImport(MapKit) && !targetEnvironment(macCatalyst)
    @available(iOS 16.0, *)
    var mapConfiguration: MKMapConfiguration {
        switch self {
        case .standard: return MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
        case .satellite: return MKImageryMapConfiguration()
        case .hybrid: return MKHybridMapConfiguration()
        }
    }
    #endif

    var mapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .satellite: return .satellite
        case .hybrid: return .hybrid
        }
    }
}

// Elevation visualization modes
enum ElevationVisualizationMode: String, CaseIterable, Identifiable {
    case effort = "Effort" // Original visualization based on effort (combining grade and distance)
    case gradient = "Gradient" // Pure elevation gradient visualization
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .effort:
            return "Colors based on combined effort (grade and distance)"
        case .gradient:
            return "Colors based purely on elevation gradient"
        }
    }
}

class SettingsModel: ObservableObject {
    @Published var userLocationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(userLocationEnabled, forKey: "userLocationEnabled")
        }
    }
    
    @Published var useMetricSystem: Bool {
        didSet {
            UserDefaults.standard.set(useMetricSystem, forKey: "useMetricSystem")
        }
    }
    
    @Published var mapStyle: MapStyle {
        didSet {
            UserDefaults.standard.set(mapStyle.rawValue, forKey: "mapStyle")
        }
    }
    
    @Published var elevationVisualizationMode: ElevationVisualizationMode {
        didSet {
            UserDefaults.standard.set(elevationVisualizationMode.rawValue, forKey: "elevationVisualizationMode")
        }
    }
    
    @Published var trackLineWidth: Double {
        didSet {
            UserDefaults.standard.set(trackLineWidth, forKey: "trackLineWidth")
        }
    }
    
    @Published var defaultShowElevationOverlay: Bool {
        didSet {
            UserDefaults.standard.set(defaultShowElevationOverlay, forKey: "defaultShowElevationOverlay")
        }
    }

    @Published var defaultShowRouteInfoOverlay: Bool {
        didSet {
            UserDefaults.standard.set(defaultShowRouteInfoOverlay, forKey: "defaultShowRouteInfoOverlay")
        }
    }
    
    @Published var chartDataDensity: Double {
        didSet {
            UserDefaults.standard.set(chartDataDensity, forKey: "chartDataDensity")
        }
    }
    
    // Calculate the stride to use for elevation chart data sampling
    var chartDataStride: Int {
        let densityFactor = chartDataDensity // 1.0 = full resolution, 0.0 = lowest resolution
        // Dynamically adjust based on density (higher value = lower stride = more points)
        // When density is 1.0, we show all points before striding
        // When density is 0.0, we show only about 200 points
        if densityFactor >= 1.0 {
            return 1 // Full resolution
        } else {
            // Scale between 10 (low density) and 1 (high density)
            let maxStride = 10
            return max(1, Int((1.0 - densityFactor) * Double(maxStride - 1) + 1))
        }
    }
    
    init() {
        // Initialize all stored properties in the correct order
        self.userLocationEnabled = UserDefaults.standard.bool(forKey: "userLocationEnabled", defaultValue: false)
        self.useMetricSystem = UserDefaults.standard.bool(forKey: "useMetricSystem", defaultValue: true)
        
        // Initialize map style
        if let savedMapStyle = UserDefaults.standard.string(forKey: "mapStyle"),
           let style = MapStyle(rawValue: savedMapStyle) {
            self.mapStyle = style
        } else {
            self.mapStyle = .standard
        }
        
        // Initialize elevation visualization mode
        if let savedVisualizationMode = UserDefaults.standard.string(forKey: "elevationVisualizationMode"),
           let mode = ElevationVisualizationMode(rawValue: savedVisualizationMode) {
            self.elevationVisualizationMode = mode
        } else {
            self.elevationVisualizationMode = .effort
        }
        
        // Initialize default elevation overlay visibility
        self.defaultShowElevationOverlay = UserDefaults.standard.bool(forKey: "defaultShowElevationOverlay", defaultValue: true)

        // Initialize default route info overlay visibility
        self.defaultShowRouteInfoOverlay = UserDefaults.standard.bool(forKey: "defaultShowRouteInfoOverlay", defaultValue: true)
        
        // Initialize track line width with a default of 4 and bounds of 2-10
        let lineWidth = UserDefaults.standard.double(forKey: "trackLineWidth")
        if lineWidth < 2 || lineWidth > 10 {
            self.trackLineWidth = 4
            UserDefaults.standard.set(4.0, forKey: "trackLineWidth")
        } else {
            self.trackLineWidth = lineWidth
        }
        
        // Initialize chart data density with a default of 0.5 (medium resolution)
        let density = UserDefaults.standard.double(forKey: "chartDataDensity")
        if density < 0 || density > 1 {
            self.chartDataDensity = 0.5
            UserDefaults.standard.set(0.5, forKey: "chartDataDensity")
        } else {
            self.chartDataDensity = density
        }
    }
    
    func formatDistance(_ distanceInMeters: Double) -> String {
        if useMetricSystem {
            let kilometers = distanceInMeters / 1000
            return String(format: "%.2f km", kilometers)
        } else {
            let miles = distanceInMeters / 1609.34
            return String(format: "%.2f mi", miles)
        }
    }
}

extension UserDefaults {
    func bool(forKey defaultName: String, defaultValue: Bool) -> Bool {
        if object(forKey: defaultName) == nil {
            set(defaultValue, forKey: defaultName)
            return defaultValue
        }
        return bool(forKey: defaultName)
    }
}
