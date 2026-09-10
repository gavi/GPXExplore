//
//  PreviewViewController.swift
//  QuickLookGPX
//
//  Created by Gavi Narra on 5/8/25.
//

import Cocoa
import Quartz
import MapKit
import CoreLocation

class PreviewViewController: NSViewController, QLPreviewingController {
    // Map view for displaying the GPX track
    private let mapView = MKMapView()
    private let statsLabel = NSTextField(wrappingLabelWithString: "")
    
    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }
    
    override func loadView() {
        super.loadView()
        
        // Setup view with a split layout - map on top, stats below
        let containerView = NSView(frame: view.bounds)
        containerView.autoresizingMask = [.width, .height]
        view = containerView
        
        
        // Configure map view (taking up top 2/3 of the space)
        let mapHeight = view.bounds.height * 0.7
        mapView.frame = CGRect(x: 0, y: view.bounds.height - mapHeight, width: view.bounds.width, height: mapHeight)
        mapView.autoresizingMask = [.width, .height]
        mapView.delegate = self
        mapView.mapType = .standard
        
        // Set some visual properties to make the empty map more visually appealing
        mapView.wantsLayer = true
        mapView.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor
        
        // Add a background label indicating map limitations
        let backgroundLabel = NSTextField(labelWithString: String(localized: "Basemap may not appear in Quick Look"))
        backgroundLabel.textColor = NSColor.tertiaryLabelColor
        backgroundLabel.alignment = .center
        backgroundLabel.font = NSFont.systemFont(ofSize: 14)
        backgroundLabel.frame = mapView.bounds
        backgroundLabel.autoresizingMask = [.width, .height]
        mapView.addSubview(backgroundLabel)
        view.addSubview(mapView)
        
        // Configure stats label (bottom 1/3)
        statsLabel.frame = CGRect(x: 10, y: 10, width: view.bounds.width - 20, height: view.bounds.height - mapHeight - 20)
        statsLabel.autoresizingMask = [.width, .height]
        statsLabel.font = NSFont.systemFont(ofSize: 12)
        statsLabel.alignment = .left
        view.addSubview(statsLabel)
    }
    
    func preparePreviewOfFile(at url: URL) async throws {
        // Parse the GPX file using existing GPXParser
        let gpxFile = GPXParser.parseGPXFile(at: url)
        
        // A file with only waypoints is still a preview
        guard !gpxFile.tracks.isEmpty || !gpxFile.waypoints.isEmpty else {
            statsLabel.stringValue = String(localized: "No tracks or waypoints found in GPX file")
            return
        }
        
        // Collect all track segments from the file
        let trackSegments = gpxFile.allSegments
        var allLocations: [CLLocation] = []
        
        // Process each segment to add to map
        for segment in trackSegments {
            let locations = segment.locations
            guard !locations.isEmpty else { continue }
            
            allLocations.append(contentsOf: locations)
            
            // One polyline per run of equal grade colour, so the preview matches the app
            for run in GradedRun.runs(for: locations) {
                let polyline = ColoredPolyline(coordinates: run.coordinates, count: run.coordinates.count)
                polyline.color = run.color
                mapView.addOverlay(polyline)
            }
        }
        
        // Add basic waypoints if any
        if !gpxFile.waypoints.isEmpty {
            let waypoints = gpxFile.waypoints.map { waypoint -> MKPointAnnotation in
                let annotation = MKPointAnnotation()
                annotation.coordinate = waypoint.coordinate
                annotation.title = waypoint.name
                return annotation
            }
            mapView.addAnnotations(waypoints)
            if allLocations.isEmpty {
                allLocations = gpxFile.waypoints.map { CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
            }
        }
        
        // Set map region to show all points
        if !allLocations.isEmpty {
            setMapRegion(for: mapView, from: allLocations)
        }
        
        // Calculate statistics for display
        var statsText = String(localized: "GPX File: \(gpxFile.filename)") + "\n\n"
        
        // Basic counts
        statsText += String(localized: "Contents:") + "\n"
        statsText += "• " + String(localized: "\(gpxFile.tracks.count) tracks") + "\n"
        statsText += "• " + String(localized: "\(gpxFile.allSegments.count) segments") + "\n"
        statsText += "• " + String(localized: "\(gpxFile.waypoints.count) waypoints") + "\n"
        
        // Calculate totals
        var totalDistance = 0.0
        var totalTime: TimeInterval = 0
        var totalAscent = 0.0
        var totalDescent = 0.0
        var pointCount = 0
        
        var hasElevation = false
        var hasTime = false
        for track in gpxFile.tracks {
            let workout = track.workout
            totalDistance += workout.totalDistance
            pointCount += track.allLocations.count
            
            // Sum elevation changes and per-segment durations, only where the file has the data
            for segment in track.segments {
                let timed = segment.locations.filter { $0.timestamp != gpxMissingTimestamp }.map { $0.timestamp }
                if let a = timed.min(), let b = timed.max() { totalTime += b.timeIntervalSince(a); hasTime = true }
                if segment.locations.count > 1 {
                    for i in 1..<segment.locations.count where segment.locations[i].verticalAccuracy >= 0 && segment.locations[i-1].verticalAccuracy >= 0 {
                        hasElevation = true
                        let elevDiff = segment.locations[i].altitude - segment.locations[i-1].altitude
                        if elevDiff > 1.0 {
                            totalAscent += elevDiff
                        } else if elevDiff < -1.0 {
                            totalDescent += abs(elevDiff)
                        }
                    }
                }
            }
        }
        
        // Format statistics
        statsText += "\n" + String(localized: "Stats:") + "\n"
        
        // Distance
        let distanceFormatter = MeasurementFormatter()
        distanceFormatter.unitOptions = .providedUnit
        distanceFormatter.numberFormatter.maximumFractionDigits = 1
        let distanceMeasurement = Measurement(value: totalDistance, unit: UnitLength.meters)
        statsText += "• " + String(localized: "Distance: \(distanceFormatter.string(from: distanceMeasurement))") + "\n"
        
        // Duration, only when the file has timestamps
        let durationFormatter = DateComponentsFormatter()
        durationFormatter.allowedUnits = [.hour, .minute, .second]
        durationFormatter.unitsStyle = .abbreviated
        if hasTime, let formattedDuration = durationFormatter.string(from: totalTime) {
            statsText += "• " + String(localized: "Duration: \(formattedDuration)") + "\n"
        }
        
        // Elevation, only when the file has it
        if hasElevation {
            let elevFormatter = MeasurementFormatter()
            elevFormatter.unitOptions = .providedUnit
            elevFormatter.numberFormatter.maximumFractionDigits = 0
            let ascentMeasurement = Measurement(value: totalAscent, unit: UnitLength.meters)
            let descentMeasurement = Measurement(value: totalDescent, unit: UnitLength.meters)
            statsText += "• " + String(localized: "Elevation Gain: \(elevFormatter.string(from: ascentMeasurement))") + "\n"
            statsText += "• " + String(localized: "Elevation Loss: \(elevFormatter.string(from: descentMeasurement))") + "\n"
        }
        statsText += "• " + String(localized: "Total Points: \(pointCount)")
        
        // Update stats label
        statsLabel.stringValue = statsText
    }
    
    // Helper method to set the map region
    private func setMapRegion(for mapView: MKMapView, from locations: [CLLocation]) {
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

// Implement MKMapViewDelegate to render the polylines
extension PreviewViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            
            // Grade colour from the run, or a flat blue when the file has no elevation
            renderer.strokeColor = (polyline as? ColoredPolyline)?.color ?? NSColor.systemBlue
            
            // Make lines thicker to be more visible even without map tiles
            renderer.lineWidth = 5.0
            
            // Add a stroke effect to make it stand out more
            renderer.lineCap = .round
            renderer.lineJoin = .round
            
            // Optional: you could add a shadow effect, though this might not render in the sandbox
            // renderer.setShadow(NSShadow())
            
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !annotation.isKind(of: MKUserLocation.self) else { return nil }
        
        let identifier = "GPXPointAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
        } else {
            annotationView?.annotation = annotation
        }
        
        if let markerView = annotationView as? MKMarkerAnnotationView {
                // Style markers differently based on type
            if annotation.title == "Start" {
                markerView.markerTintColor = .systemGreen
                markerView.glyphText = "S"
            } else if annotation.title == "End" {
                markerView.markerTintColor = .systemRed
                markerView.glyphText = "E"
            } else {
                // Waypoint styling
                markerView.markerTintColor = .systemBlue
                markerView.glyphText = "W"
            }
        }
        
        return annotationView
    }
}

// A polyline that knows its colour: one per run of points sharing a grade bucket
final class ColoredPolyline: MKPolyline {
    var color: NSColor = .systemBlue
}

// Grade colouring for the preview, a compact copy of the app's TrackColors/TrackGrades
// (the extension cannot link the app target). Keep the thresholds and colours in step.
enum GradedRun {
    struct Run { let coordinates: [CLLocationCoordinate2D]; let color: NSColor }

    static func color(forGrade g: Double) -> NSColor {
        let c = min(max(g, -0.15), 0.15)
        if c >= 0 {
            if c < 0.03 { return NSColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1) }
            if c < 0.08 { return NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1) }
            return NSColor(red: 1.0, green: 0.1, blue: 0.0, alpha: 1)
        }
        let a = -c
        if a < 0.03 { return NSColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 1) }
        if a < 0.08 { return NSColor(red: 0.0, green: 0.3, blue: 0.9, alpha: 1) }
        return NSColor(red: 0.3, green: 0.0, blue: 0.8, alpha: 1)
    }

    static func runs(for locations: [CLLocation]) -> [Run] {
        let n = locations.count
        guard n > 1 else { return [] }
        let hasElevation = locations.contains { $0.verticalAccuracy >= 0 }
        guard hasElevation else { return [Run(coordinates: locations.map { $0.coordinate }, color: NSColor(red: 0.2, green: 0.45, blue: 0.95, alpha: 1))] }
        // smooth, then windowed grade, as the app does
        var ele = locations.map { $0.altitude }
        if n > 3 {
            let w = min(5, n / 20 + 2); let src = ele
            for i in 0..<n { let lo = max(0, i - w), hi = min(n - 1, i + w); ele[i] = src[lo...hi].reduce(0, +) / Double(hi - lo + 1) }
        }
        var grades = Array(repeating: 0.0, count: n)
        let window = min(5, n / 10 + 1)
        for i in 0..<(n - 1) {
            let lo = max(0, i - window), hi = min(n - 1, i + window)
            guard hi > lo else { continue }
            let dist = locations[lo].distance(from: locations[hi])
            if dist > 5 { grades[i] = min(max((ele[hi] - ele[lo]) / dist, -0.45), 0.45) }
        }
        grades[n - 1] = grades[n - 2]
        // group consecutive points by colour; each run overlaps its neighbour by one point
        var runs: [Run] = []
        var current: [CLLocationCoordinate2D] = [locations[0].coordinate]
        var currentColor = color(forGrade: grades[0])
        for i in 1..<n {
            let c = color(forGrade: grades[i - 1])
            if c != currentColor {
                runs.append(Run(coordinates: current, color: currentColor))
                current = [locations[i - 1].coordinate]
                currentColor = c
            }
            current.append(locations[i].coordinate)
        }
        runs.append(Run(coordinates: current, color: currentColor))
        return runs
    }
}
