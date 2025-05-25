import SwiftUI
import MapKit
import CoreLocation
import UIKit

// iOS-specific MapView implementation
struct MapView: UIViewRepresentable, MapViewShared {
    let trackSegments: [GPXTrackSegment]
    let waypoints: [GPXWaypoint]
    @EnvironmentObject var settings: SettingsModel

    // Optional center point for when a waypoint is selected from the drawer
    var centerCoordinate: CLLocationCoordinate2D?
    var zoomLevel: Double? // Optional zoom level, default will be used if nil
    var spanAll: Bool = false // Trigger to span the view to show all content
    var hoveredPointIndex: Int? = nil // Index of point being hovered in the chart

    // Convenience init to maintain backward compatibility
    init(routeLocations: [CLLocation]) {
        self.trackSegments = [GPXTrackSegment(locations: routeLocations, trackIndex: 0)]
        self.waypoints = []
        self.centerCoordinate = nil
        self.zoomLevel = nil
        self.spanAll = false
        self.hoveredPointIndex = nil
    }
    
    // New initializer for multiple segments
    init(trackSegments: [GPXTrackSegment]) {
        self.trackSegments = trackSegments
        self.waypoints = []
        self.centerCoordinate = nil
        self.zoomLevel = nil
        self.spanAll = false
    }
    
    // New initializer for segments and waypoints
    init(trackSegments: [GPXTrackSegment], waypoints: [GPXWaypoint]) {
        self.trackSegments = trackSegments
        self.waypoints = waypoints
        self.centerCoordinate = nil
        self.zoomLevel = nil
        self.spanAll = false
    }
    
    // New initializer for centering on a specific waypoint
    init(trackSegments: [GPXTrackSegment], waypoints: [GPXWaypoint], centerCoordinate: CLLocationCoordinate2D?, zoomLevel: Double? = nil, spanAll: Bool = false, hoveredPointIndex: Int? = nil) {
        self.trackSegments = trackSegments
        self.waypoints = waypoints
        self.centerCoordinate = centerCoordinate
        self.zoomLevel = zoomLevel
        self.spanAll = spanAll
        self.hoveredPointIndex = hoveredPointIndex
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        
        // Only show user location if permission is granted
        mapView.showsUserLocation = settings.userLocationEnabled && 
            (CLLocationManager().authorizationStatus == .authorizedWhenInUse || 
             CLLocationManager().authorizationStatus == .authorizedAlways)
        
        // Disable the built-in tracking button since we're adding our own
        mapView.showsUserTrackingButton = false
        
        // Initialize location controls - they will be managed dynamically in updateUIView
        context.coordinator.setupLocationControls(mapView: mapView, enabled: settings.userLocationEnabled)
        
        // Store reference to the mapView in the coordinator for permission handling
        context.coordinator.mapView = mapView
        
        // Store if this is initial load to perform delayed zoom in
        context.coordinator.isInitialLoad = true
        
        #if swift(>=5.7) && !targetEnvironment(macCatalyst)
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = settings.mapStyle.mapConfiguration
        } else {
            mapView.mapType = settings.mapStyle.mapType
        }
        #else
        mapView.mapType = settings.mapStyle.mapType
        #endif
        
        // Skip if no segments
        if trackSegments.isEmpty {
            return mapView
        }
        
        // Collect all locations for region setting
        var allLocations: [CLLocation] = []
        
        // Store all polylines for the coordinator
        var elevationPolylines: [ElevationPolyline] = []
        
        // Process each segment separately
        for (index, segment) in trackSegments.enumerated() {
            let locations = segment.locations
            guard !locations.isEmpty else { continue }
            
            // Add locations for region calculation later
            allLocations.append(contentsOf: locations)
            
            // Create the enhanced elevation polyline for this segment
            let elevationPolyline = createElevationPolyline(from: locations)
            
            // Calculate grade data (this will smooth and process elevation data)
            elevationPolyline.calculateGradeData(from: locations)
            
            // Debug elevation data
            print("=== SEGMENT \(index+1) ELEVATION DATA SUMMARY ===")
            print("Total points: \(elevationPolyline.elevations.count)")
            print("Min elevation: \(elevationPolyline.minElevation)m")
            print("Max elevation: \(elevationPolyline.maxElevation)m")
            print("Total ascent: \(elevationPolyline.totalAscent)m")
            print("Total descent: \(elevationPolyline.totalDescent)m")
            print("Grade range: \(elevationPolyline.minGrade) to \(elevationPolyline.maxGrade)")
            if !elevationPolyline.grades.isEmpty {
                let nonZeroGrades = elevationPolyline.grades.filter { abs($0) > 0.005 }
                print("Non-zero grades count: \(nonZeroGrades.count) of \(elevationPolyline.grades.count)")
                
                // Sample some grades
                if nonZeroGrades.count > 0 {
                    let sampleCount = min(5, nonZeroGrades.count)
                    print("Sample grades: \(nonZeroGrades.prefix(sampleCount))")
                }
            }
            print("==============================")
            
            // Add to map
            mapView.addOverlay(elevationPolyline)
            
            // Store the polyline for the coordinator
            elevationPolylines.append(elevationPolyline)
        }
        
        // Store elevation polylines in coordinator for renderer to use
        context.coordinator.elevationPolylines = elevationPolylines
        
        // Set the visible region to show all tracks
        if !allLocations.isEmpty {
            // Add significant elevation markers (Garmin-like)
            addElevationMarkers(to: mapView, routeLocations: allLocations)
            
            // Set the region to show all segments
            MapView.setRegion(for: mapView, from: allLocations)
            
            // Add start and end annotations using the first and last segments
            if let firstSegment = trackSegments.first, 
               let lastSegment = trackSegments.last,
               let firstLocation = firstSegment.locations.first,
               let lastLocation = lastSegment.locations.last {
                
                let startPoint = MKPointAnnotation()
                startPoint.coordinate = firstLocation.coordinate
                startPoint.title = "Start"
                
                let endPoint = MKPointAnnotation()
                endPoint.coordinate = lastLocation.coordinate
                endPoint.title = "End"
                
                mapView.addAnnotations([startPoint, endPoint])
            }
            
            // Add waypoint annotations
            if !waypoints.isEmpty {
                let waypointAnnotations = waypoints.map { WaypointAnnotation(waypoint: $0) }
                mapView.addAnnotations(waypointAnnotations)
                print("Added \(waypointAnnotations.count) waypoint annotations to map")
            }
            
            // Store the locations for delayed zoom (this will be applied in updateUIView)
            context.coordinator.initialLoadLocations = allLocations
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update map configuration if settings changed
        #if swift(>=5.7) && !targetEnvironment(macCatalyst)
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = settings.mapStyle.mapConfiguration
        } else {
            mapView.mapType = settings.mapStyle.mapType
        }
        #else
        mapView.mapType = settings.mapStyle.mapType
        #endif
        
        // Update user location visibility based on settings and permissions
        let authStatus = CLLocationManager().authorizationStatus
        mapView.showsUserLocation = settings.userLocationEnabled && 
            (authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways)
        
        // Dynamically manage location controls based on settings
        context.coordinator.setupLocationControls(mapView: mapView, enabled: settings.userLocationEnabled)

        // Always update when this method is called to ensure visibility changes are reflected
        // This handles both segment count changes and visibility toggling

        // Get existing overlays before clearing
        let existingOverlaysCount = mapView.overlays.count

        // Get annotations by type for more granular control
        let existingHoverAnnotations = mapView.annotations.filter { $0.title == "Hover Point" }
        let existingWaypointAnnotations = mapView.annotations.filter { $0 is WaypointAnnotation }
        let existingMarkerAnnotations = mapView.annotations.filter {
            $0.title == "Start" || $0.title == "End" || $0.title == "Peak" || $0.title == "Valley"
        }
        let existingHoverAnnotation = existingHoverAnnotations.first

        // We only need to update markers (Start, End, Peak, Valley) when the track segments change
        let shouldUpdateMarkers = (existingOverlaysCount != trackSegments.count) || existingMarkerAnnotations.isEmpty

        // Only remove waypoint annotations if they should not be visible
        let shouldShowWaypoints = !waypoints.isEmpty
        if !shouldShowWaypoints && !existingWaypointAnnotations.isEmpty {
            mapView.removeAnnotations(existingWaypointAnnotations)
        }

        // Only remove marker annotations if we need to update them (segments changed)
        if shouldUpdateMarkers && !existingMarkerAnnotations.isEmpty {
            mapView.removeAnnotations(existingMarkerAnnotations)
        }

        // 3. Clear existing overlays
        context.coordinator.clearOverlays(from: mapView)

        // Skip if no segments to show
        if trackSegments.isEmpty && waypoints.isEmpty {
            context.coordinator.elevationPolylines = []
            return
        }

        // Add each segment's polyline
        var newElevationPolylines: [ElevationPolyline] = []
        for segment in trackSegments {
            let elevationPolyline = createElevationPolyline(from: segment.locations)
            elevationPolyline.calculateGradeData(from: segment.locations)
            mapView.addOverlay(elevationPolyline)
            newElevationPolylines.append(elevationPolyline)
        }

        // Update the coordinator's polylines
        context.coordinator.elevationPolylines = newElevationPolylines

        // Collect all locations
        let allLocations = trackSegments.flatMap { $0.locations }

        // Add hover point annotation if there's a hovered point with throttling
        if let hoveredIndex = hoveredPointIndex, hoveredIndex >= 0 && hoveredIndex < allLocations.count {
            // Apply throttling to reduce excessive map updates
            let now = Date()
            let timeSinceLastUpdate = now.timeIntervalSince(context.coordinator.lastHoverUpdateTime)
            let isDifferentIndex = hoveredIndex != context.coordinator.lastHoveredIndex

            // Only update if sufficient time has passed or it's a different point
            if timeSinceLastUpdate >= context.coordinator.hoverThrottleInterval || isDifferentIndex {
                let hoverLocation = allLocations[hoveredIndex]

                // Format elevation for subtitle
                let elevation = hoverLocation.altitude
                let formattedElevation = settings.useMetricSystem
                    ? String(format: "%.0f m", elevation)
                    : String(format: "%.0f ft", elevation * 3.28084)

                if let existingPoint = existingHoverAnnotation as? MKPointAnnotation {
                    // Check if the annotation would move a significant distance
                    // This reduces map flicker by avoiding tiny position updates
                    let existingCoord = existingPoint.coordinate
                    let newCoord = hoverLocation.coordinate

                    // Calculate rough distance (not perfect but very fast)
                    let latDiff = abs(existingCoord.latitude - newCoord.latitude)
                    let lonDiff = abs(existingCoord.longitude - newCoord.longitude)
                    let significantMove = (latDiff > 0.0001 || lonDiff > 0.0001)

                    // Only update position if it changed significantly (reduces flicker)
                    if significantMove {
                        // Update existing annotation coordinate
                        existingPoint.coordinate = newCoord
                    }

                    // Always update subtitle to show current elevation, but only if changed
                    let newSubtitle = "Elevation: \(formattedElevation)"
                    if existingPoint.subtitle != newSubtitle {
                        existingPoint.subtitle = newSubtitle
                    }

                    // Don't call setNeedsDisplay - this causes flickering
                } else {
                    // Need to add a new one - remove all existing hover annotations first
                    if !existingHoverAnnotations.isEmpty {
                        mapView.removeAnnotations(existingHoverAnnotations)
                    }

                    // Create new hover point
                    let hoverPoint = MKPointAnnotation()
                    hoverPoint.coordinate = hoverLocation.coordinate
                    hoverPoint.title = "Hover Point"
                    hoverPoint.subtitle = "Elevation: \(formattedElevation)"
                    mapView.addAnnotation(hoverPoint)
                }

                // Don't auto-zoom on hover - let the user control map position
                // This dramatically improves performance

                // Update tracking properties
                context.coordinator.lastHoverUpdateTime = now
                context.coordinator.lastHoveredIndex = hoveredIndex
            }
        }

        // We'll only add static annotations (waypoints, start/end) if needed

        // Add waypoint annotations but only if they should be visible and aren't already shown
        // This prevents unnecessary removes and adds during hover events
        var waypointAnnotations: [WaypointAnnotation] = []
        if !waypoints.isEmpty && existingWaypointAnnotations.isEmpty {
            waypointAnnotations = waypoints.map { WaypointAnnotation(waypoint: $0) }
            mapView.addAnnotations(waypointAnnotations)
        }

        if !allLocations.isEmpty && shouldUpdateMarkers {
            // Add elevation markers and start/end annotations only when needed
            addElevationMarkers(to: mapView, routeLocations: allLocations)

            // Add start and end annotations
            if let firstSegment = trackSegments.first,
               let lastSegment = trackSegments.last,
               let firstLocation = firstSegment.locations.first,
               let lastLocation = lastSegment.locations.last {

                let startPoint = MKPointAnnotation()
                startPoint.coordinate = firstLocation.coordinate
                startPoint.title = "Start"

                let endPoint = MKPointAnnotation()
                endPoint.coordinate = lastLocation.coordinate
                endPoint.title = "End"

                mapView.addAnnotations([startPoint, endPoint])
            }
        }
        
        // Check if we need to center on a specific waypoint
        if let center = centerCoordinate {
            // Center the map on the specified coordinate with animation
            let span = MKCoordinateSpan(
                latitudeDelta: zoomLevel ?? 0.01,  // Default zoom if not specified
                longitudeDelta: zoomLevel ?? 0.01
            )
            let region = MKCoordinateRegion(center: center, span: span)
            mapView.setRegion(region, animated: true)
            
            // Highlight the selected waypoint if it exists
            if let waypointAnnotation = waypointAnnotations.first(where: { 
                $0.coordinate.latitude == center.latitude && 
                $0.coordinate.longitude == center.longitude 
            }) {
                // Select the annotation to show its callout
                mapView.selectAnnotation(waypointAnnotation, animated: true)
            }
        }
        // Check if we need to span to show all content
        else if spanAll {
            // Combine all track locations and waypoints
            var allLocations = trackSegments.flatMap { $0.locations }
            
            // Add waypoint locations if there are any
            if !waypoints.isEmpty {
                let waypointLocations = waypoints.map { 
                    CLLocation(
                        coordinate: $0.coordinate, 
                        altitude: $0.elevation ?? 0,
                        horizontalAccuracy: 10,
                        verticalAccuracy: 10,
                        timestamp: $0.timestamp ?? Date()
                    )
                }
                allLocations.append(contentsOf: waypointLocations)
            }
            
            if !allLocations.isEmpty {
                // Set region to fit everything with animation
                MapView.setRegion(for: mapView, from: allLocations)
                
                // Add a slight delay to ensure the map has time to process the region change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    // Apply a slight animation to make the zoom more smooth
                    UIView.animate(withDuration: 0.3) {
                        mapView.setRegion(mapView.region, animated: false)
                    }
                }
            }
        }
        // Otherwise handle normal region setting
        else if context.coordinator.isInitialLoad {
            // Collect all locations
            if !allLocations.isEmpty {
                print("Setting up delayed zoom for initial load")
                context.coordinator.performDelayedZoom(mapView: mapView, locations: allLocations)
            }
        } 
        // Regular region setting (for cases other than initial load)
        else {
            // Adjust the map view region in these cases:
            // 1. First time showing segments (existingOverlaysCount == 0)
            // 2. When showing tracks after they were hidden (existingOverlaysCount != newElevationPolylines.count)
            // 3. Always set region on iOS to ensure consistent behavior
            let shouldSetRegion = (!newElevationPolylines.isEmpty && 
                                 (existingOverlaysCount == 0 || 
                                  existingOverlaysCount != newElevationPolylines.count))
                                 || (newElevationPolylines.isEmpty && !waypoints.isEmpty)
            
            if shouldSetRegion {
                if !allLocations.isEmpty {
                    // Set the map region to fit all visible segments
                    MapView.setRegion(for: mapView, from: allLocations)
                } else if !waypoints.isEmpty {
                    // If we only have waypoints, set region to show all waypoints
                    let waypointLocations = waypoints.map { 
                        CLLocation(
                            coordinate: $0.coordinate, 
                            altitude: $0.elevation ?? 0,
                            horizontalAccuracy: 10,
                            verticalAccuracy: 10,
                            timestamp: $0.timestamp ?? Date()
                        )
                    }
                    MapView.setRegion(for: mapView, from: waypointLocations)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}

extension Coordinator {
    // Handle user location updates by implementing the MKMapViewDelegate method
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        // This is called when the user's location updates
        // When in user tracking mode, the map will automatically move with the user
        print("User location updated: \(userLocation.coordinate.latitude), \(userLocation.coordinate.longitude)")
    }
    
    // Handle changes to user tracking mode
    func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
        print("User tracking mode changed to: \(mode.rawValue)")
    }
    
    // Perform a delayed zoom for initial load (iOS only)
    func performDelayedZoom(mapView: MKMapView, locations: [CLLocation]) {
        // Cancel any existing timer
        delayedZoomTimer?.invalidate()
        
        // Setup a timer to perform the delayed zoom (500ms delay)
        delayedZoomTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            print("Performing delayed zoom after initial load")
            
            MapView.setRegion(for: mapView, from: locations)
            
            // Reset initial load flag
            self.isInitialLoad = false
            self.initialLoadLocations = nil
        }
    }
    
    // Handle the callout accessory control tap (copy coordinates button)
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        print("Copy button tapped in callout")
        guard let annotation = view.annotation else {
            print("No annotation found")
            return
        }
        
        // Format coordinates for clipboard
        let coordinate = annotation.coordinate
        let lat = String(format: "%.6f", coordinate.latitude)
        let lon = String(format: "%.6f", coordinate.longitude)
        let coordinateString = "\(lat), \(lon)"
        
        print("Copying coordinates: \(coordinateString)")
        
        // Copy to clipboard
        UIPasteboard.general.string = coordinateString
        
        // Provide haptic feedback - this is reliable and doesn't require a view controller
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Try multiple methods to show visual feedback
        print("Attempting to show feedback alert")
        
        // Method 1: Using the superview chain
        if let viewController = view.superview?.findViewController() {
            print("Found view controller via superview chain")
            let alert = UIAlertController(
                title: "Coordinates Copied",
                message: "Location coordinates have been copied to clipboard",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
        }
        // Method 2: Using the window's root view controller
        else if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let window = scene.windows.first,
                let rootVC = window.rootViewController {
            print("Found root view controller via window")
            let alert = UIAlertController(
                title: "Coordinates Copied",
                message: "Location coordinates have been copied to clipboard",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            // Handle the case if root view controller is presenting something
            var topVC = rootVC
            while let presentedVC = topVC.presentedViewController {
                topVC = presentedVC
            }
            
            topVC.present(alert, animated: true)
        } else {
            print("Could not find a suitable view controller for showing alert")
            // Just rely on haptic feedback in this case
        }
    }
}
