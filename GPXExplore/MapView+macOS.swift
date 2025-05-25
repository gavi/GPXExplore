import SwiftUI
import MapKit
import CoreLocation

// macOS-specific MapView implementation
struct MapView: NSViewRepresentable, MapViewShared {
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
    
    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = settings.userLocationEnabled
        
        // Set up compass and other controls
        if #available(macOS 11.0, *) {
            mapView.showsCompass = true
            mapView.showsZoomControls = true
            // On macOS, we don't have a standard user tracking button,
            // but we can add one via MKCompassButton when needed
        }
        
        #if swift(>=5.7)
        if #available(macOS 13.0, *) {
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
        }
        
        return mapView
    }
    
    func updateNSView(_ mapView: MKMapView, context: Context) {
        // Update map configuration if settings changed
        #if swift(>=5.7)
        if #available(macOS 13.0, *) {
            mapView.preferredConfiguration = settings.mapStyle.mapConfiguration
        } else {
            mapView.mapType = settings.mapStyle.mapType
        }
        #else
        mapView.mapType = settings.mapStyle.mapType
        #endif
        
        // Update user location visibility based on settings
        mapView.showsUserLocation = settings.userLocationEnabled
        

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

        // Skip if no segments or waypoints to show
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

        // Only add static annotations (waypoints, start/end) if they don't already exist
        let existingStaticAnnotations = mapView.annotations.filter { $0.title != "Hover Point" }
        let hasStaticAnnotations = !existingStaticAnnotations.isEmpty

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
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.3
                        mapView.setRegion(mapView.region, animated: false)
                    }
                }
            }
        }
        // Otherwise handle normal region setting
        else {
            // Adjust the map view region in these cases:
            // 1. First time showing segments (existingOverlaysCount == 0)
            // 2. When showing tracks after they were hidden (existingOverlaysCount != newElevationPolylines.count)
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
    
    // Handle the click for the copy button on macOS
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: NSControl) {
        print("Copy button tapped in callout (macOS)")
        guard let annotation = view.annotation else {
            print("No annotation found")
            return
        }
        
        // Format coordinates for clipboard
        let coordinate = annotation.coordinate
        let lat = String(format: "%.6f", coordinate.latitude)
        let lon = String(format: "%.6f", coordinate.longitude)
        let coordinateString = "\(lat), \(lon)"
        
        print("Copying coordinates to macOS pasteboard: \(coordinateString)")
        
        // Copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(coordinateString, forType: .string)
        
        // Show feedback (could be expanded to use NSPopover or similar)
        print("Successfully copied coordinates to clipboard")
    }
}