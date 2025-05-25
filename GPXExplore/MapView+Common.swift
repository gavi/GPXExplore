import SwiftUI
import MapKit
import CoreLocation

#if os(iOS)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
#endif

// Enhanced polyline object to store elevation data and gradients
class ElevationPolyline: MKPolyline {
    // Basic elevation data
    var elevations: [CLLocationDistance] = []
    var minElevation: CLLocationDistance = 0
    var maxElevation: CLLocationDistance = 0
    
    // Enhanced data for Garmin-like visualization
    var grades: [Double] = []        // Store the grade (steepness) between each point
    var maxGrade: Double = 0         // Maximum grade (uphill)
    var minGrade: Double = 0         // Minimum grade (downhill)
    var totalAscent: Double = 0      // Total elevation gain
    var totalDescent: Double = 0     // Total elevation loss
    
    // Calculate enhanced statistics after setting elevations
    func calculateGradeData(from locations: [CLLocation]) {
        guard locations.count > 1 && elevations.count == locations.count else { 
            print("ERROR: Cannot calculate grade data - invalid locations or elevations")
            return 
        }
        
        // First, smooth the elevation data to reduce GPS noise
        smoothElevationData()
        
        var currentAscent: Double = 0
        var currentDescent: Double = 0
        grades = Array(repeating: 0, count: elevations.count)
        
        // Use a sliding window for calculating grades to reduce noise
        let windowSize = min(5, locations.count / 10 + 1) // Adaptive window size
        print("Using window size \(windowSize) for \(locations.count) locations")
        
        for i in 0..<(locations.count - 1) {
            // Calculate start and end indices for the window
            let startIdx = max(0, i - windowSize)
            let endIdx = min(locations.count - 1, i + windowSize)
            
            if endIdx > startIdx {
                // Use points at the edges of the window for more stable grade calculation
                let elevation1 = elevations[startIdx]
                let elevation2 = elevations[endIdx]
                let location1 = locations[startIdx]
                let location2 = locations[endIdx]
                
                // Calculate horizontal distance over the window
                let horizontalDistance = location1.distance(from: location2)
                
                // Calculate grade (avoid division by zero)
                var grade = 0.0
                if horizontalDistance > 5.0 { // Require more substantial distance for good grade calculation
                    grade = (elevation2 - elevation1) / horizontalDistance
                    
                    // Apply realistic limits to grades (real-world trails rarely exceed 35%)
                    grade = min(max(grade, -0.45), 0.45)
                    
                    // Debug every 20th point to avoid console flood
                    if i % 20 == 0 {
                        //print("Point \(i): window \(startIdx)-\(endIdx), elev diff: \(elevation2-elevation1)m, " +
                              //"horiz dist: \(horizontalDistance)m, grade: \(originalGrade) → \(grade)")
                    }
                } else if i % 20 == 0 {
                    //print("Point \(i): window \(startIdx)-\(endIdx), horizontal distance too small (\(horizontalDistance)m)")
                }
                
                // Preserve small grade changes rather than zeroing them out
                // This ensures subtle elevation changes are still visible on the map
                // (Previously we were setting grades < 0.005 to 0.0)
                
                // Store the grade
                grades[i] = grade
                
                // Update max/min grade
                if i == 0 || grade > maxGrade {
                    maxGrade = grade
                }
                if i == 0 || grade < minGrade {
                    minGrade = grade
                }
            }
            
            // Still calculate ascent/descent point-to-point for accuracy
            if i > 0 {
                let elevationDiff = elevations[i] - elevations[i-1]
                // Only count significant elevation changes (>1m) to avoid noise
                if elevationDiff > 1.0 {
                    currentAscent += elevationDiff
                } else if elevationDiff < -1.0 {
                    currentDescent += abs(elevationDiff)
                }
            }
        }
        
        // Store final values
        totalAscent = currentAscent
        totalDescent = currentDescent
        
        // Set the last grade to match the previous to avoid gaps
        if grades.count > 1 {
            grades[grades.count - 1] = grades[grades.count - 2]
        }
    }
    
    // Smooth elevation data using a moving average
    private func smoothElevationData() {
        guard elevations.count > 3 else { return }
        
        // Create a copy of the original elevations
        let originalElevations = elevations
        
        // Window size for smoothing (adaptive to route length)
        let windowSize = min(5, elevations.count / 20 + 2)
        
        // Apply moving average smoothing
        for i in 0..<elevations.count {
            var sum: Double = 0
            var count: Double = 0
            
            // Calculate window boundaries
            let windowStart = max(0, i - windowSize)
            let windowEnd = min(originalElevations.count - 1, i + windowSize)
            
            // Sum elevations in window
            for j in windowStart...windowEnd {
                sum += originalElevations[j]
                count += 1
            }
            
            // Set smoothed elevation
            if count > 0 {
                elevations[i] = sum / count
            }
        }
    }
    
    // Helper method to get statistics formatted for display
    func getStatisticsDescription() -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        
        let ascentMeasurement = Measurement(value: totalAscent, unit: UnitLength.meters)
        let descentMeasurement = Measurement(value: totalDescent, unit: UnitLength.meters)
        
        let maxGradePercent = abs(maxGrade * 100)
        let minGradePercent = abs(minGrade * 100)
        
        return """
        Total Ascent: \(formatter.string(from: ascentMeasurement))
        Total Descent: \(formatter.string(from: descentMeasurement))
        Max Uphill Grade: \(String(format: "%.1f", maxGradePercent))%
        Max Downhill Grade: \(String(format: "%.1f", minGradePercent))%
        """
    }
}

// Original effort-based gradient polyline renderer
class GradientPolylineRenderer: MKPolylineRenderer {
    var elevationPolyline: ElevationPolyline?
    var callCounter: Int = 0
    
    // Constants for grade calculation - reduced to show more color variation
    private let minSignificantGrade: Double = 0.005  // 0.5% grade - flat/slight
    private let moderateGrade: Double = 0.03        // 3% grade - moderate
    private let steepGrade: Double = 0.08          // 8% grade - steep
    private let verysteepGrade: Double = 0.15      // 15% grade - very steep
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        guard let elevationPolyline = elevationPolyline else {
            super.draw(mapRect, zoomScale: zoomScale, in: ctx)
            return
        }

        // Start by getting the polyline's points in map coordinates
        let points = polyline.points()
        let pointCount = polyline.pointCount
        
        // We need at least 2 points to draw a line
        if pointCount < 2 {
            super.draw(mapRect, zoomScale: zoomScale, in: ctx)
            return
        }
        
        // Calculate line width with zoom adjustments
        let baseLineWidth = self.lineWidth // Use the lineWidth property set from outside
        let adjustedLineWidth = baseLineWidth / zoomScale

        // Set up the context for drawing
        ctx.saveGState()
        ctx.setLineWidth(adjustedLineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        
        // Draw each segment with its corresponding color
        for i in 0..<(pointCount-1) {
            // Get map points for the segment
            let pointA = points[i]
            let pointB = points[i+1]
            
            // Convert to points in the renderer's coordinate system
            let pixelPointA = point(for: MKMapPoint(x: pointA.x, y: pointA.y))
            let pixelPointB = point(for: MKMapPoint(x: pointB.x, y: pointB.y))
            
            // Check if this segment is visible in the current map rect
            let segmentRect = MKMapRect(x: min(pointA.x, pointB.x),
                                       y: min(pointA.y, pointB.y),
                                       width: abs(pointB.x - pointA.x),
                                       height: abs(pointB.y - pointA.y))
            
            // Only draw if segment is visible
            if mapRect.intersects(segmentRect) {
                // Prevent out of bounds access
                let indexA = min(i, elevationPolyline.elevations.count - 1)
                let indexB = min(i+1, elevationPolyline.elevations.count - 1)
                
                // Get elevations at both points
                let elevationA = elevationPolyline.elevations[indexA]
                let elevationB = elevationPolyline.elevations[indexB]
                
                // Calculate the horizontal distance between points (in meters)
                let metersPerMapPoint = MKMetersPerMapPointAtLatitude(pointA.y)
                let dx = (pointB.x - pointA.x) * metersPerMapPoint
                let dy = (pointB.y - pointA.y) * metersPerMapPoint
                let horizontalDistance = sqrt(dx*dx + dy*dy)
                
                // Calculate grade (rise/run) if we have a significant horizontal distance
                var grade = 0.0
                
                // Try to use precomputed grades first if available
                if !elevationPolyline.grades.isEmpty && indexA < elevationPolyline.grades.count {
                    grade = elevationPolyline.grades[indexA]
                    //print("Segment \(i): Using precomputed grade: \(grade)")
                }
                // If grade is zero or grades aren't available, calculate it
                else if horizontalDistance > 1.0 {  // Avoid division by very small numbers
                    grade = (elevationB - elevationA) / horizontalDistance
                    
                    // Debug elevation info
                    //print("Segment \(i): elevA=\(elevationA), elevB=\(elevationB), diff=\(elevationB-elevationA), horizDist=\(horizontalDistance), rawGrade=\(grade)")
                    
                    // Filter out unrealistic grades from GPS noise
                    // Real-world roads/trails rarely exceed 30-35% grade
                    if abs(grade) > 0.5 {  // 50% grade cutoff for realism
                        // Apply a more reasonable limit
                        grade = grade > 0 ? 0.35 : -0.35
                        //print("  Clamping grade from previous value to \(grade)")
                    }
                    
                    // Apply a minimum threshold to avoid flat line when elevation is changing
                    if abs(grade) < 0.01 && abs(elevationB - elevationA) > 0.5 {
                        grade = (elevationB > elevationA) ? 0.01 : -0.01
                        //print("  Boosting small grade to \(grade)")
                    }
                } else {
                    //print("Segment \(i): Horizontal distance too small (\(horizontalDistance)m), using grade=0")
                }
                
                // Apply color for this grade
                let color = colorForGrade(grade)
                
                // Set stroke color for this segment
                ctx.setStrokeColor(color.cgColor)
                
                // Draw the segment
                ctx.beginPath()
                ctx.move(to: pixelPointA)
                ctx.addLine(to: pixelPointB)
                ctx.strokePath()
            }
        }
        
        ctx.restoreGState()
    }
    
    // Get color based on grade (Garmin-like)
    private func colorForGrade(_ grade: Double) -> PlatformColor {
        // Ensure grade is in a reasonable range
        let clampedGrade = min(max(grade, -verysteepGrade), verysteepGrade)
        
        // Enable non-gray colors for flat sections
        // Set to true to show flat sections as colored
        let forceNonGrayColors = true
        
        // Only log every 10th call to avoid console flood
        var callCounter = self.callCounter
        callCounter += 1
        if callCounter % 20 == 0 {
            //print("colorForGrade call #\(callCounter): input: \(grade), clamped: \(clampedGrade)")
        }
        self.callCounter = callCounter
        
        // Color schemes based on Garmin's approach
        // Uphill: green to yellow to orange to red
        // Downhill: light blue to darker blue
        // Flat: gray
        
        if clampedGrade > 0 || (forceNonGrayColors && grade >= 0) {
            // Uphill or flat treated as slight uphill
            if clampedGrade < minSignificantGrade && !forceNonGrayColors {
                // Flat to slight uphill: gray (only if not forcing colors)
                return PlatformColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            } else if clampedGrade < moderateGrade {
                // Force more vibrant colors rather than subtle gradient
                // Use multiple distinct colors instead of blending
                
                // Slight uphill: vibrant green
                return PlatformColor(
                    red: 0.0,
                    green: 0.8,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else if clampedGrade < steepGrade {
                // Moderate uphill: bright orange
                return PlatformColor(
                    red: 1.0,
                    green: 0.6,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else if clampedGrade < verysteepGrade {
                // Steep uphill: bright red
                return PlatformColor(
                    red: 1.0,
                    green: 0.1,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else {
                // Very steep uphill: bright red
                return PlatformColor(red: 1.0, green: 0.1, blue: 0, alpha: 1.0)
            }
        } else {
            // Downhill (using absolute value of grade for calculations)
            let absGrade = abs(clampedGrade)
            
            if absGrade < minSignificantGrade && !forceNonGrayColors {
                // Flat to slight downhill: gray (only if not forcing colors)
                return PlatformColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            } else if absGrade < moderateGrade {
                // Light blue for slight downhill
                return PlatformColor(
                    red: 0.0,
                    green: 0.5,
                    blue: 1.0,
                    alpha: 1.0
                )
            } else if absGrade < steepGrade {
                // Medium blue for moderate downhill
                return PlatformColor(
                    red: 0.0,
                    green: 0.3,
                    blue: 0.9,
                    alpha: 1.0
                )
            } else if absGrade < verysteepGrade {
                // Deep blue/purple for steep downhill
                return PlatformColor(
                    red: 0.3,
                    green: 0.0,
                    blue: 0.8,
                    alpha: 1.0
                )
            } else {
                // Very steep downhill: purple
                return PlatformColor(red: 0.4, green: 0.2, blue: 0.8, alpha: 1.0)
            }
        }
    }
}

// New pure elevation gradient polyline renderer
class ElevationGradientPolylineRenderer: MKPolylineRenderer {
    var elevationPolyline: ElevationPolyline?
    var callCounter: Int = 0
    
    // Constants for color range
    private let minSignificantValue: Double = 0.05  // 5% of range - slight color change
    private let moderateValue: Double = 0.3        // 30% of range - moderate color change
    private let strongValue: Double = 0.6          // 60% of range - strong color change
    private let extremeValue: Double = 0.85        // 85% of range - extreme color change
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        guard let elevationPolyline = elevationPolyline else {
            super.draw(mapRect, zoomScale: zoomScale, in: ctx)
            return
        }

        // Start by getting the polyline's points in map coordinates
        let points = polyline.points()
        let pointCount = polyline.pointCount
        
        // We need at least 2 points to draw a line
        if pointCount < 2 {
            super.draw(mapRect, zoomScale: zoomScale, in: ctx)
            return
        }
        
        // Calculate line width with zoom adjustments
        let baseLineWidth = self.lineWidth // Use the lineWidth property set from outside
        let adjustedLineWidth = baseLineWidth / zoomScale

        // Set up the context for drawing
        ctx.saveGState()
        ctx.setLineWidth(adjustedLineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        
        // Draw each segment with its corresponding color
        for i in 0..<(pointCount-1) {
            // Get map points for the segment
            let pointA = points[i]
            let pointB = points[i+1]
            
            // Convert to points in the renderer's coordinate system
            let pixelPointA = point(for: MKMapPoint(x: pointA.x, y: pointA.y))
            let pixelPointB = point(for: MKMapPoint(x: pointB.x, y: pointB.y))
            
            // Check if this segment is visible in the current map rect
            let segmentRect = MKMapRect(x: min(pointA.x, pointB.x),
                                       y: min(pointA.y, pointB.y),
                                       width: abs(pointB.x - pointA.x),
                                       height: abs(pointB.y - pointA.y))
            
            // Only draw if segment is visible
            if mapRect.intersects(segmentRect) {
                // Prevent out of bounds access
                let indexA = min(i, elevationPolyline.elevations.count - 1)
                
                // Get current elevation
                let elevation = elevationPolyline.elevations[indexA]
                
                // Calculate normalized elevation (0 to 1 scale)
                var normalizedElevation = 0.5 // Default to middle (gray) if no elevation range
                
                if elevationPolyline.maxElevation > elevationPolyline.minElevation {
                    normalizedElevation = (elevation - elevationPolyline.minElevation) / 
                                         (elevationPolyline.maxElevation - elevationPolyline.minElevation)
                }
                
                // Get color based on normalized elevation
                let color = colorForNormalizedElevation(normalizedElevation)
                
                // Set stroke color for this segment
                ctx.setStrokeColor(color.cgColor)
                
                // Draw the segment
                ctx.beginPath()
                ctx.move(to: pixelPointA)
                ctx.addLine(to: pixelPointB)
                ctx.strokePath()
            }
        }
        
        ctx.restoreGState()
    }
    
    // Get color based on normalized elevation (0-1 scale)
    private func colorForNormalizedElevation(_ value: Double) -> PlatformColor {
        // Ensure value is in 0-1 range
        let clampedValue = min(max(value, 0.0), 1.0)
        
        // Only log every 10th call to avoid console flood
        var callCounter = self.callCounter
        callCounter += 1
        if callCounter % 20 == 0 {
            //print("colorForNormalizedElevation call #\(callCounter): input: \(value), clamped: \(clampedValue)")
        }
        self.callCounter = callCounter
        
        // Color scheme for elevation:
        // Low: Deep blue -> Medium blue -> Light blue
        // Middle: Green/Yellow
        // High: Yellow -> Orange -> Red
        
        if clampedValue < 0.5 {
            // Lower half of elevation range (0.0-0.5 mapped to 0.0-1.0)
            let scaledValue = clampedValue * 2 // Scale to 0-1 range
            
            if scaledValue < minSignificantValue {
                // Deepest blue - lowest elevation
                return PlatformColor(
                    red: 0.0,
                    green: 0.0,
                    blue: 0.8,
                    alpha: 1.0
                )
            } else if scaledValue < moderateValue {
                // Medium blue
                return PlatformColor(
                    red: 0.0,
                    green: 0.3,
                    blue: 0.9,
                    alpha: 1.0
                )
            } else if scaledValue < strongValue {
                // Light blue
                return PlatformColor(
                    red: 0.0,
                    green: 0.6,
                    blue: 1.0,
                    alpha: 1.0
                )
            } else {
                // Cyan - approaching middle elevation
                return PlatformColor(
                    red: 0.0,
                    green: 0.8,
                    blue: 0.8,
                    alpha: 1.0
                )
            }
        } else {
            // Upper half of elevation range (0.5-1.0 mapped to 0.0-1.0)
            let scaledValue = (clampedValue - 0.5) * 2 // Scale to 0-1 range
            
            if scaledValue < minSignificantValue {
                // Green - just above middle elevation
                return PlatformColor(
                    red: 0.1,
                    green: 0.8,
                    blue: 0.1,
                    alpha: 1.0
                )
            } else if scaledValue < moderateValue {
                // Yellow-green
                return PlatformColor(
                    red: 0.6,
                    green: 0.8,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else if scaledValue < strongValue {
                // Yellow/orange
                return PlatformColor(
                    red: 1.0,
                    green: 0.6,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else if scaledValue < extremeValue {
                // Orange/red - high elevation
                return PlatformColor(
                    red: 1.0,
                    green: 0.3,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else {
                // Bright red - highest elevation
                return PlatformColor(
                    red: 1.0,
                    green: 0.0,
                    blue: 0.0,
                    alpha: 1.0
                )
            }
        }
    }
}

// Custom annotation for waypoints
class WaypointAnnotation: NSObject, MKAnnotation {
    let waypoint: GPXWaypoint
    var _subtitle: String?

    var coordinate: CLLocationCoordinate2D {
        return waypoint.coordinate
    }

    var title: String? {
        return waypoint.name
    }

    var subtitle: String? {
        // Return custom subtitle if set, otherwise fallback to waypoint description
        return _subtitle ?? waypoint.description
    }

    init(waypoint: GPXWaypoint) {
        self.waypoint = waypoint
        super.init()

        // Subtitle will be set in the mapView(_:viewFor:) method
        // We don't set default values here to allow the view to determine them
    }
}

// Custom annotation for elevation hover points
class HoverPointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let elevation: Double
    let useMetric: Bool

    var title: String? {
        return "Hover Point"
    }

    var subtitle: String? {
        // Format elevation with proper units
        let formattedElevation = useMetric
            ? String(format: "%.0f m", elevation)
            : String(format: "%.0f ft", elevation * 3.28084)

        return "Elevation: \(formattedElevation)"
    }

    init(coordinate: CLLocationCoordinate2D, elevation: Double, useMetric: Bool) {
        self.coordinate = coordinate
        self.elevation = elevation
        self.useMetric = useMetric
        super.init()
    }
}

// Shared MapView functionality
protocol MapViewShared {
    var trackSegments: [GPXTrackSegment] { get }
    var waypoints: [GPXWaypoint] { get }
    var centerCoordinate: CLLocationCoordinate2D? { get }
    var zoomLevel: Double? { get }
    var spanAll: Bool { get }
    var hoveredPointIndex: Int? { get }
}

// Helper functions shared by both platforms
extension MapViewShared {
    func createElevationPolyline(from locations: [CLLocation]) -> ElevationPolyline {
        let coordinates = locations.map { $0.coordinate }
        let elevations = locations.map { $0.altitude }
        
        // Create the polyline with coordinates
        let elevationPolyline = ElevationPolyline(coordinates: coordinates, count: coordinates.count)
        
        // Store the elevations
        elevationPolyline.elevations = elevations
        
        // Calculate min and max elevations for scaling the gradient
        if let minEle = elevations.min(), let maxEle = elevations.max() {
            elevationPolyline.minElevation = minEle
            elevationPolyline.maxElevation = maxEle
        }
        
        return elevationPolyline
    }
    
    func addElevationMarkers(to mapView: MKMapView, routeLocations: [CLLocation]) {
        guard routeLocations.count > 10 else { return }
        
        let elevations = routeLocations.map { $0.altitude }
        
        // Find local maxima and minima that are significant
        var significantPoints: [(index: Int, elevation: Double, isMax: Bool)] = []
        let windowSize = max(routeLocations.count / 20, 5) // Adaptive window size
        
        for i in windowSize..<(routeLocations.count - windowSize) {
            let currentElev = elevations[i]
            
            // Check if this is a local maximum
            var isLocalMax = true
            for j in (i-windowSize)...(i+windowSize) {
                if j != i && elevations[j] > currentElev {
                    isLocalMax = false
                    break
                }
            }
            
            // Check if this is a local minimum
            var isLocalMin = true
            for j in (i-windowSize)...(i+windowSize) {
                if j != i && elevations[j] < currentElev {
                    isLocalMin = false
                    break
                }
            }
            
            // Only add points that are significantly different from their surroundings
            if isLocalMax || isLocalMin {
                // Calculate average elevation in the window
                var sum = 0.0
                for j in (i-windowSize)...(i+windowSize) {
                    sum += elevations[j]
                }
                let avgElev = sum / Double(2 * windowSize + 1)
                
                // Check if the difference is significant (>= 10 meters)
                let elevDiff = abs(currentElev - avgElev)
                if elevDiff >= 10 {
                    significantPoints.append((i, currentElev, isLocalMax))
                }
            }
        }
        
        // Add elevation markers for significant points (limit to avoid clutter)
        let maxMarkers = 5
        if significantPoints.count > maxMarkers {
            // Sort by elevation difference and take top ones
            significantPoints.sort { abs($0.elevation) > abs($1.elevation) }
            significantPoints = Array(significantPoints.prefix(maxMarkers))
        }
        
        // Create annotations for these points
        for point in significantPoints {
            let annotation = MKPointAnnotation()
            annotation.coordinate = routeLocations[point.index].coordinate
            
            let elevationFormatted = Int(round(point.elevation))
            annotation.title = point.isMax ? "Peak" : "Valley"
            annotation.subtitle = "\(elevationFormatted)m"
            
            mapView.addAnnotation(annotation)
        }
    }
    
    static func setRegion(for mapView: MKMapView, from locations: [CLLocation]) {
        guard !locations.isEmpty else { return }
        
        // Find min/max coordinates
        var minLat = locations[0].coordinate.latitude
        var maxLat = minLat
        var minLon = locations[0].coordinate.longitude
        var maxLon = minLon
        
        for location in locations {
            minLat = min(minLat, location.coordinate.latitude)
            maxLat = max(maxLat, location.coordinate.latitude)
            minLon = min(minLon, location.coordinate.longitude)
            maxLon = max(maxLon, location.coordinate.longitude)
        }
        
        // Create region with padding
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5,
            longitudeDelta: (maxLon - minLon) * 1.5
        )
        
        // Ensure minimum zoom level
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(span.latitudeDelta, 0.01),
                longitudeDelta: max(span.longitudeDelta, 0.01)
            )
        )
        
        mapView.setRegion(region, animated: false)
    }
}

// Shared Coordinator class that can be used with both UIViewRepresentable and NSViewRepresentable
class Coordinator: NSObject, MKMapViewDelegate {
    var elevationPolylines: [ElevationPolyline] = []
    var isInitialLoad: Bool = false
    var initialLoadLocations: [CLLocation]? = nil
    var delayedZoomTimer: Timer? = nil
    var lastHoverUpdateTime: Date = Date.distantPast // Track when we last updated hover point
    var lastHoveredIndex: Int? = nil // Track the last hovered point index
    let hoverThrottleInterval: TimeInterval = 0.25 // Throttle hover updates to 4 per second
    
    // Location management
    weak var mapView: MKMapView?
    
    // Location controls references (iOS only)
    #if os(iOS)
    private weak var compassButton: MKCompassButton?
    private weak var userTrackingButton: MKUserTrackingButton?
    #endif
    
    override init() {
        super.init()
    }
    
    deinit {
        delayedZoomTimer?.invalidate()
        
        // Disable MapKit's user location display to stop its automatic location updates
        mapView?.showsUserLocation = false
        mapView?.setUserTrackingMode(.none, animated: false)
        
        print("Coordinator deallocated - stopped location updates")
    }
    
    // Keep the single polyline property for backward compatibility
    var elevationPolyline: ElevationPolyline? {
        get {
            return elevationPolylines.first
        }
        set {
            if let newValue = newValue {
                elevationPolylines = [newValue]
            } else {
                elevationPolylines = []
            }
        }
    }
    
    // Clear all overlays from the map
    func clearOverlays(from mapView: MKMapView) {
        mapView.removeOverlays(mapView.overlays)
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? ElevationPolyline {
            // Get settings from the MapView through the coordinator
            guard let modeString = UserDefaults.standard.string(forKey: "elevationVisualizationMode"),
                  let mode = ElevationVisualizationMode(rawValue: modeString) else {
                // Default to effort if setting not found
                let gradientRenderer = GradientPolylineRenderer(polyline: polyline)
                gradientRenderer.elevationPolyline = polyline
                gradientRenderer.lineWidth = 4  // Increased line width for better visibility
                return gradientRenderer
            }
            
            // Select renderer based on the visualization mode
            // Get the track line width from UserDefaults
            let lineWidth = UserDefaults.standard.double(forKey: "trackLineWidth")
            // Use the saved line width (with fallback to 4 if not set)
            let finalLineWidth = lineWidth >= 2 && lineWidth <= 10 ? lineWidth : 4
            
            switch mode {
            case .effort:
                // Create original effort-based gradient polyline renderer
                let gradientRenderer = GradientPolylineRenderer(polyline: polyline)
                gradientRenderer.elevationPolyline = polyline
                gradientRenderer.lineWidth = finalLineWidth
                return gradientRenderer
                
            case .gradient:
                // Create pure elevation gradient polyline renderer
                let elevationRenderer = ElevationGradientPolylineRenderer(polyline: polyline)
                elevationRenderer.elevationPolyline = polyline
                elevationRenderer.lineWidth = finalLineWidth
                return elevationRenderer
            }
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !annotation.isKind(of: MKUserLocation.self) else { return nil }

        // Special handling for hover point
        if annotation.title == "Hover Point" {
            let identifier = "HoverPin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }

            if let markerView = annotationView as? MKMarkerAnnotationView {
                // Use bright highlight color for hover point
                markerView.markerTintColor = .systemRed

#if os(iOS)
                markerView.glyphImage = UIImage(systemName: "location.fill")
                markerView.animatesWhenAdded = true
#elseif os(macOS)
                // Use SF Symbols on macOS 11+
                if #available(macOS 11.0, *) {
                    markerView.glyphImage = NSImage(systemSymbolName: "location.fill", accessibilityDescription: "Current Point")
                } else {
                    markerView.glyphText = "•"
                }
#endif

                // Make hover point more prominent
                markerView.displayPriority = .required
            }

            return annotationView
        }

        // Use a different identifier for waypoints
        let identifier = annotation is WaypointAnnotation ? "WaypointPin" : "WorkoutPin"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
        } else {
            annotationView?.annotation = annotation
        }

        if let markerView = annotationView as? MKMarkerAnnotationView {
            // Handle waypoint annotations
            if let waypointAnnotation = annotation as? WaypointAnnotation {
                markerView.markerTintColor = .purple
#if os(iOS)
                markerView.glyphImage = UIImage(systemName: "mappin")
                // Add a button for copying coordinates
                let button = UIButton(type: .custom)
                button.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
                button.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
                button.tintColor = UIColor.systemBlue
                annotationView?.rightCalloutAccessoryView = button
#elseif os(macOS)
                // Use SF Symbols on macOS 11+
                if #available(macOS 11.0, *) {
                    markerView.glyphImage = NSImage(systemSymbolName: "mappin", accessibilityDescription: "Waypoint")
                } else {
                    // Fallback for older macOS versions
                    markerView.glyphText = "W"
                }
                // Add a button for copying coordinates on macOS
                let button = NSButton(title: "Copy", target: nil, action: nil)
                button.bezelStyle = .rounded
                annotationView?.rightCalloutAccessoryView = button
#endif

                // Set subtitle based on waypoint description if available, otherwise use coordinates
                if let description = waypointAnnotation.waypoint.description, !description.isEmpty {
                    waypointAnnotation._subtitle = description
                } else {
                    // Fallback to coordinates if no description
                    let coordinate = waypointAnnotation.coordinate
                    let lat = String(format: "%.6f", coordinate.latitude)
                    let lon = String(format: "%.6f", coordinate.longitude)
                    waypointAnnotation._subtitle = "\(lat), \(lon)"
                }

                // Use custom glyph based on waypoint symbol if available
                if let symbol = waypointAnnotation.waypoint.symbol {
                    // Common GPX symbols can be mapped to SF Symbols
                    let iconName: String
                    switch symbol.lowercased() {
                    case "flag", "summit":
                        iconName = "flag"
                    case "campground", "camp":
                        iconName = "tent"
                    case "water", "drinking-water":
                        iconName = "drop"
                    case "parking":
                        iconName = "car"
                    case "info", "information":
                        iconName = "info.circle"
                    case "danger", "caution":
                        iconName = "exclamationmark.triangle"
                    case "restaurant", "food":
                        iconName = "fork.knife"
                    default:
                        iconName = "mappin"
                    }

#if os(iOS)
                    markerView.glyphImage = UIImage(systemName: iconName)
#elseif os(macOS)
                    if #available(macOS 11.0, *) {
                        markerView.glyphImage = NSImage(systemSymbolName: iconName, accessibilityDescription: symbol)
                    }
#endif
                }

                // Set priority for waypoints (higher than elevation markers)
                markerView.displayPriority = .defaultHigh
            }
            // Set appearance based on annotation type for track markers
            else if annotation.title == "Start" {
                markerView.markerTintColor = .green
#if os(iOS)
                markerView.glyphImage = UIImage(systemName: "flag.fill")
#elseif os(macOS)
                // Use SF Symbols on macOS 11+
                if #available(macOS 11.0, *) {
                    markerView.glyphImage = NSImage(systemSymbolName: "flag.fill", accessibilityDescription: "Start")
                } else {
                    // Fallback for older macOS versions
                    markerView.glyphText = "S"
                }
#endif
            } else if annotation.title == "End" {
                markerView.markerTintColor = .red
#if os(iOS)
                markerView.glyphImage = UIImage(systemName: "flag.checkered")
#elseif os(macOS)
                // Use SF Symbols on macOS 11+
                if #available(macOS 11.0, *) {
                    markerView.glyphImage = NSImage(systemSymbolName: "flag.checkered", accessibilityDescription: "End")
                } else {
                    // Fallback for older macOS versions
                    markerView.glyphText = "E"
                }
#endif
            } else if annotation.title == "Peak" {
                markerView.markerTintColor = .orange
#if os(iOS)
                markerView.glyphImage = UIImage(systemName: "arrow.up")
#elseif os(macOS)
                markerView.glyphText = "▲"
#endif
                markerView.displayPriority = .defaultLow // Lower priority to avoid clutter
            } else if annotation.title == "Valley" {
                markerView.markerTintColor = .blue
#if os(iOS)
                markerView.glyphImage = UIImage(systemName: "arrow.down")
#elseif os(macOS)
                markerView.glyphText = "▼"
#endif
                markerView.displayPriority = .defaultLow // Lower priority to avoid clutter
            }
        }

        return annotationView
    }
    
    
    #if os(iOS)
    func setupLocationControls(mapView: MKMapView, enabled: Bool) {
        if enabled {
            // Add compass button if not already present
            if compassButton == nil {
                let compass = MKCompassButton(mapView: mapView)
                compass.compassVisibility = .visible
                mapView.addSubview(compass)
                compass.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    compass.centerYAnchor.constraint(equalTo: mapView.centerYAnchor),
                    compass.leadingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.leadingAnchor, constant: 20)
                ])
                compassButton = compass
            }
            
            // Add user tracking button if not already present
            if userTrackingButton == nil {
                let trackingButton = MKUserTrackingButton(mapView: mapView)
                trackingButton.layer.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.7).cgColor
                trackingButton.layer.cornerRadius = 5
                trackingButton.layer.borderWidth = 1
                trackingButton.layer.borderColor = UIColor.systemGray.cgColor
                mapView.addSubview(trackingButton)
                trackingButton.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    trackingButton.centerYAnchor.constraint(equalTo: mapView.centerYAnchor),
                    trackingButton.trailingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.trailingAnchor, constant: -20)
                ])
                userTrackingButton = trackingButton
            }
            
            // Ensure buttons are visible
            compassButton?.isHidden = false
            userTrackingButton?.isHidden = false
        } else {
            // When location is disabled, stop any active user tracking and hide buttons
            if mapView.userTrackingMode != .none {
                mapView.setUserTrackingMode(.none, animated: true)
            }
            
            // Disable MapKit's user location display to stop automatic location updates
            mapView.showsUserLocation = false
            
            // Hide buttons when disabled
            compassButton?.isHidden = true
            userTrackingButton?.isHidden = true
        }
    }
    #endif
}