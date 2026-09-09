//
//  GPXParserBridge.swift
//  QuickLookGPX
//
//  Created by Gavi Narra on 5/8/25.
//

import Foundation
import MapKit
import CoreLocation

// Types needed from the main app
struct GPXWaypoint {
    let name: String
    let description: String?
    let coordinate: CLLocationCoordinate2D
    let elevation: Double?
    let timestamp: Date?
    let symbol: String?
}

struct GPXTrackSegment {
    let locations: [CLLocation]
    let trackIndex: Int
}

struct GPXTrack {
    var name: String
    let type: String
    let date: Date
    let segments: [GPXTrackSegment]
    
    var allLocations: [CLLocation] {
        return segments.flatMap { $0.locations }
    }
    
    var workout: GPXWorkout {
        // Simplified workout creation for QuickLook
        let allLocations = self.allLocations
        let sortedLocations = allLocations.sorted { $0.timestamp < $1.timestamp }
        
        var startDate = sortedLocations.first?.timestamp ?? date
        var endDate = sortedLocations.last?.timestamp ?? date.addingTimeInterval(3600)
        
        if endDate <= startDate {
            startDate = Date()
            endDate = startDate.addingTimeInterval(3600)
        }
        
        var totalDistanceMeters: Double = 0
        if allLocations.count > 1 {
            for i in 0..<(allLocations.count - 1) {
                totalDistanceMeters += allLocations[i].distance(from: allLocations[i+1])
            }
        }
        
        return GPXWorkout(
            activityType: "activity",
            startDate: startDate,
            endDate: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalDistance: totalDistanceMeters,
            metadata: [
                "name": name,
                "source": "GPX File"
            ]
        )
    }
}

struct GPXWorkout {
    let activityType: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let totalDistance: Double
    let metadata: [String: String]
}

struct GPXFile {
    let filename: String
    let tracks: [GPXTrack]
    let waypoints: [GPXWaypoint]
    
    var primaryTrack: GPXTrack? {
        tracks.first
    }
    
    var allSegments: [GPXTrackSegment] {
        tracks.flatMap { $0.segments }
    }
}

// Bridge class to access the main app's GPXParser
class GPXParser {
    static func parseGPXFile(at url: URL) -> GPXFile {
        // Simplified parser for QuickLook that reads XML directly
        guard let data = try? Data(contentsOf: url) else {
            return GPXFile(filename: url.lastPathComponent, tracks: [], waypoints: [])
        }
        
        let parser = XMLParser(data: data)
        let delegate = GPXParserDelegate()
        parser.delegate = delegate
        
        if parser.parse() {
            return GPXFile(
                filename: url.deletingPathExtension().lastPathComponent,
                tracks: delegate.tracks,
                waypoints: delegate.waypoints
            )
        } else {
            return GPXFile(filename: url.lastPathComponent, tracks: [], waypoints: [])
        }
    }
}

// Simplified parser delegate for QuickLook
// ISO 8601 with or without fractional seconds, and zone-less stamps read as UTC (same rules as the app)
enum GPXDate {
    private static let fractional: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let plain: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    private static let zoneless: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f }()
    static func parse(_ text: String) -> Date? { plain.date(from: text) ?? fractional.date(from: text) ?? zoneless.date(from: text) }
}
let gpxMissingTimestamp = Date(timeIntervalSince1970: 0)

class GPXParserDelegate: NSObject, XMLParserDelegate {
    private var currentElement = ""
    
    // GPX metadata
    private var gpxMetadataDate = Date()
    
    // Current track data
    private var currentTrackName = ""
    private var currentTrackType = ""
    private var currentTrackDate = Date()
    
    // Current waypoint data
    private var currentWaypointName = ""
    private var currentWaypointDesc: String?
    private var currentWaypointSymbol: String?
    
    // Track the current element context
    private var isTrack = false
    private var isTrackSegment = false
    private var isTrackPoint = false
    private var isRoute = false
    private var isRoutePoint = false
    private var isMetadata = false
    private var isWaypoint = false
    
    // Data for the current point
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentTime: Date?
    
    // Store segments for the current track
    private var currentSegmentPoints: [CLLocation] = []
    private var currentTrackSegments: [GPXTrackSegment] = []
    
    // Store points for the current route
    private var currentRoutePoints: [CLLocation] = []
    
    // Store all completed tracks and waypoints
    private var completedTracks: [GPXTrack] = []
    private var completedWaypoints: [GPXWaypoint] = []
    
    // Public property to access all parsed tracks
    var tracks: [GPXTrack] {
        // Check if we have an in-progress track that needs to be finalized
        finalizeCurrentTrackIfNeeded()
        return completedTracks
    }
    
    // Public property to access all parsed waypoints
    var waypoints: [GPXWaypoint] {
        return completedWaypoints
    }
    
    // Finalize the current track if it has any segments with points
    private func finalizeCurrentTrackIfNeeded() {
        if !currentTrackSegments.isEmpty && !currentTrackSegments.allSatisfy({ $0.locations.isEmpty }) {
            let currentTrackIndex = completedTracks.count
            
            // Update all segments with the correct track index
            let segmentsWithTrackIndex = currentTrackSegments.map { segment in
                GPXTrackSegment(locations: segment.locations, trackIndex: currentTrackIndex)
            }
            
            let track = GPXTrack(
                name: currentTrackName.isEmpty ? "Track \(currentTrackIndex + 1)" : currentTrackName,
                type: currentTrackType,
                date: currentTrackDate.timeIntervalSince1970 > 0 ? currentTrackDate : gpxMetadataDate,
                segments: segmentsWithTrackIndex
            )
            completedTracks.append(track)
            
            // Reset current track data
            currentTrackName = ""
            currentTrackType = ""
            currentTrackDate = Date()
            currentTrackSegments = []
        }
    }
    
    // Finalize the current route if it has any points by converting it to a track
    private func finalizeCurrentRouteIfNeeded() {
        if !currentRoutePoints.isEmpty {
            let currentTrackIndex = completedTracks.count
            
            // Create a single segment from all route points
            let segment = GPXTrackSegment(locations: currentRoutePoints, trackIndex: currentTrackIndex)
            
            let track = GPXTrack(
                name: currentTrackName.isEmpty ? "Route \(currentTrackIndex + 1)" : currentTrackName,
                type: "route",
                date: currentTrackDate.timeIntervalSince1970 > 0 ? currentTrackDate : gpxMetadataDate,
                segments: [segment]
            )
            completedTracks.append(track)
            
            // Reset current route data
            currentTrackName = ""
            currentTrackType = ""
            currentTrackDate = Date()
            currentRoutePoints = []
        }
    }
    
    static func coordinate(from attributes: [String: String]) -> (Double, Double)? {
        guard let a = attributes["lat"], let b = attributes["lon"], let lat = Double(a), let lon = Double(b),
              lat >= -90, lat <= 90, lon >= -180, lon <= 180 else { return nil }
        return (lat, lon)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        switch elementName {
        case "metadata":
            isMetadata = true
            
        case "trk":
            finalizeCurrentTrackIfNeeded()
            isTrack = true
            currentTrackSegments = []
            currentTrackName = ""
            currentTrackType = ""
            currentTrackDate = Date()
            
        case "rte":
            finalizeCurrentRouteIfNeeded()
            isRoute = true
            currentRoutePoints = []
            currentTrackName = ""
            currentTrackType = ""
            currentTrackDate = Date()
            
        case "trkseg":
            isTrackSegment = true
            currentSegmentPoints = []
            
        case "trkpt":
            isTrackPoint = true
            let pair = Self.coordinate(from: attributeDict)
            currentLat = pair?.0
            currentLon = pair?.1
            currentEle = nil
            currentTime = nil
            
        case "rtept":
            isRoutePoint = true
            let pair = Self.coordinate(from: attributeDict)
            currentLat = pair?.0
            currentLon = pair?.1
            currentEle = nil
            currentTime = nil
            
        case "wpt":
            isWaypoint = true
            let pair = Self.coordinate(from: attributeDict)
            currentLat = pair?.0
            currentLon = pair?.1
            currentEle = nil
            currentTime = nil
            currentWaypointName = ""
            currentWaypointDesc = nil
            currentWaypointSymbol = nil
            
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedString.isEmpty else { return }
        
        if isTrackPoint {
            switch currentElement {
            case "ele":
                currentEle = Double(trimmedString)
            case "time":
                currentTime = GPXDate.parse(trimmedString)
            default:
                break
            }
        } else if isRoutePoint {
            switch currentElement {
            case "ele":
                currentEle = Double(trimmedString)
            case "time":
                currentTime = GPXDate.parse(trimmedString)
            default:
                break
            }
        } else if isWaypoint {
            switch currentElement {
            case "ele":
                currentEle = Double(trimmedString)
            case "time":
                currentTime = GPXDate.parse(trimmedString)
            case "name":
                currentWaypointName = trimmedString
            case "desc":
                currentWaypointDesc = trimmedString
            case "sym":
                currentWaypointSymbol = trimmedString
            default:
                break
            }
        } else if isTrack {
            switch currentElement {
            case "name":
                currentTrackName = trimmedString
            case "type":
                currentTrackType = trimmedString
            case "time":
                if let date = GPXDate.parse(trimmedString) {
                    currentTrackDate = date
                }
            default:
                break
            }
        } else if isRoute {
            switch currentElement {
            case "name":
                currentTrackName = trimmedString
            case "type":
                currentTrackType = trimmedString
            case "time":
                if let date = GPXDate.parse(trimmedString) {
                    currentTrackDate = date
                }
            default:
                break
            }
        } else if isMetadata {
            // Handle metadata elements
            switch currentElement {
            case "time":
                if let date = GPXDate.parse(trimmedString) {
                    gpxMetadataDate = date
                }
            default:
                break
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "metadata":
            isMetadata = false
            
        case "trkpt":
            if isTrackPoint, let lat = currentLat, let lon = currentLon {
                let location = CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    altitude: currentEle ?? 0,
                    horizontalAccuracy: 10,
                    verticalAccuracy: currentEle == nil ? -1 : 10,
                    timestamp: currentTime ?? gpxMissingTimestamp
                )
                currentSegmentPoints.append(location)
            }
            isTrackPoint = false
            
        case "rtept":
            if isRoutePoint, let lat = currentLat, let lon = currentLon {
                let location = CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    altitude: currentEle ?? 0,
                    horizontalAccuracy: 10,
                    verticalAccuracy: currentEle == nil ? -1 : 10,
                    timestamp: currentTime ?? gpxMissingTimestamp
                )
                currentRoutePoints.append(location)
            }
            isRoutePoint = false
            
        case "wpt":
            if isWaypoint, let lat = currentLat, let lon = currentLon {
                let waypoint = GPXWaypoint(
                    name: currentWaypointName.isEmpty ? "POI" : currentWaypointName,
                    description: currentWaypointDesc,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    elevation: currentEle,
                    timestamp: currentTime,
                    symbol: currentWaypointSymbol
                )
                completedWaypoints.append(waypoint)
            }
            isWaypoint = false
            
        case "trkseg":
            // End of segment - add it to the current track's segments
            if !currentSegmentPoints.isEmpty {
                // Use a placeholder track index that will be updated in finalizeCurrentTrackIfNeeded
                let segment = GPXTrackSegment(locations: currentSegmentPoints, trackIndex: -1)
                currentTrackSegments.append(segment)
            }
            isTrackSegment = false
            
        case "trk":
            // End of track - finalize it
            finalizeCurrentTrackIfNeeded()
            isTrack = false
            
        case "rte":
            // End of route - finalize it
            finalizeCurrentRouteIfNeeded()
            isRoute = false
            
        case "gpx":
            // End of file - make sure we've finalized any in-progress track or route
            finalizeCurrentTrackIfNeeded()
            finalizeCurrentRouteIfNeeded()
            
        default:
            break
        }
        
        currentElement = ""
    }
}
