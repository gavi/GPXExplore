import Foundation
import CoreLocation

// A GPX <link>: href plus optional text and MIME type (GPX 1.0 <url>/<urlname> map here too)
struct GPXLink: Equatable {
    let href: String
    let text: String?
    let type: String?
}

// <author> in GPX 1.1 (name, email, link); GPX 1.0's plain-text author lands in `name`
struct GPXPerson: Equatable {
    let name: String?
    let email: String?
    let link: GPXLink?
}

struct GPXBounds: Equatable {
    let minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double
}

// <metadata>, complete: what CoreGPX exposes as GPXMetadata
struct GPXMetadata: Equatable {
    var name: String?
    var description: String?
    var author: GPXPerson?
    var copyrightAuthor: String?
    var copyrightYear: String?
    var copyrightLicense: String?
    var links: [GPXLink] = []
    var time: Date?
    var keywords: String?
    var bounds: GPXBounds?
    var extensions: [String: String] = [:]   // leaf elements under <extensions>, local name → text
}

// Sensor readings attached to one track point through GPX <extensions> (Garmin
// TrackPointExtension, PowerExtension, or the bare <power> most services exchange).
// Every field is optional: most files carry none, WorkoutGPX and watches carry some.
struct SensorSample: Equatable {
    var heartRate: Double?    // beats per minute
    var cadence: Double?      // steps or revolutions per minute
    var power: Double?        // watts
    var temperature: Double?  // °C
    var speed: Double?        // m/s, as recorded (not derived)

    // The rest of what a <trkpt>/<rtept> may carry (GPX 1.1 wptType), kept so nothing is dropped
    var name: String?
    var comment: String?
    var description: String?
    var source: String?
    var symbol: String?
    var type: String?
    var fix: String?          // none, 2d, 3d, dgps, pps
    var satellites: Int?
    var hdop: Double?
    var vdop: Double?
    var pdop: Double?
    var magneticVariation: Double?
    var geoidHeight: Double?
    var ageOfDGPSData: Double?
    var dgpsId: Int?
    var links: [GPXLink]?
    var extra: [String: String]?   // extension leaves not mapped above, local name → text

    var isEmpty: Bool { heartRate == nil && cadence == nil && power == nil && temperature == nil && speed == nil }
}

// Represents a track segment with location points
struct GPXTrackSegment: Equatable {
    let locations: [CLLocation]
    let trackIndex: Int  // Reference to which track this segment belongs to
    // One sample per location (same count). Empty samples when the file has no extensions.
    let samples: [SensorSample]
    // False when no point in the file carried <ele>: altitudes are placeholders then
    // (0, verticalAccuracy -1) and nothing elevation-based should be shown.
    let hasElevation: Bool
    // False when no point carried <time>: timestamps are placeholders (epoch 0).
    let hasTimestamps: Bool

    init(locations: [CLLocation], trackIndex: Int, samples: [SensorSample] = [], hasElevation: Bool = true, hasTimestamps: Bool = true) {
        self.locations = locations
        self.trackIndex = trackIndex
        self.samples = samples.count == locations.count ? samples : Array(repeating: SensorSample(), count: locations.count)
        self.hasElevation = hasElevation
        self.hasTimestamps = hasTimestamps
    }

    var hasHeartRate: Bool { samples.contains { $0.heartRate != nil } }
    var hasCadence: Bool { samples.contains { $0.cadence != nil } }
    var hasPower: Bool { samples.contains { $0.power != nil } }
    var hasTemperature: Bool { samples.contains { $0.temperature != nil } }
    var hasSpeed: Bool { samples.contains { $0.speed != nil } }
    
    static func == (lhs: GPXTrackSegment, rhs: GPXTrackSegment) -> Bool {
        guard lhs.locations.count == rhs.locations.count && lhs.trackIndex == rhs.trackIndex else { return false }
        
        for i in 0..<lhs.locations.count {
            let loc1 = lhs.locations[i]
            let loc2 = rhs.locations[i]
            
            // Compare essential properties
            if loc1.coordinate.latitude != loc2.coordinate.latitude ||
               loc1.coordinate.longitude != loc2.coordinate.longitude ||
               loc1.altitude != loc2.altitude ||
               loc1.timestamp != loc2.timestamp {
                return false
            }
        }
        
        return true
    }
}

struct GPXTrack {
    var name: String
    let type: String
    let date: Date
    // Updated to support multiple track segments
    let segments: [GPXTrackSegment]
    // The rest of trkType / rteType
    let comment: String?
    let description: String?
    let source: String?
    let links: [GPXLink]
    let number: Int?
    let isRoute: Bool                   // came from <rte>, flattened into one segment
    let extensions: [String: String]    // leaf elements under the track's <extensions>

    init(name: String, type: String, date: Date, segments: [GPXTrackSegment],
         comment: String? = nil, description: String? = nil, source: String? = nil, links: [GPXLink] = [],
         number: Int? = nil, isRoute: Bool = false, extensions: [String: String] = [:]) {
        self.name = name; self.type = type; self.date = date; self.segments = segments
        self.comment = comment; self.description = description; self.source = source; self.links = links
        self.number = number; self.isRoute = isRoute; self.extensions = extensions
    }
    
    // Convenience computed property to get all locations across all segments
    var allLocations: [CLLocation] {
        return segments.flatMap { $0.locations }
    }

    var hasTimestamps: Bool { segments.contains { $0.hasTimestamps } }
    var hasElevation: Bool { segments.contains { $0.hasElevation } }
    
    var activityType: String {
        // Check filename first for simulator samples
        let lowercaseName = name.lowercased()
        if lowercaseName.contains("run") || lowercaseName.contains("running") {
            return "running"
        } else if lowercaseName.contains("bike") || lowercaseName.contains("cycling") {
            return "cycling"
        } else if lowercaseName.contains("hike") || lowercaseName.contains("hiking") {
            return "hiking"
        }
        
        // Then check type field
        switch type.lowercased() {
        case "running":
            return "running"
        case "cycling":
            return "cycling"
        case "hiking":
            return "hiking"
        default:
            return "other"
        }
    }
    
    var workout: GPXWorkout {
        // Create a workout representation for the GPX track
        // Use sorted locations to ensure start and end dates are correct
        let allLocations = self.allLocations
        let sortedLocations = allLocations.sorted { $0.timestamp < $1.timestamp }
        
        // Without timestamps the workout has no duration; never invent one
        let startDate: Date
        let endDate: Date
        if hasTimestamps, let first = sortedLocations.first?.timestamp, let last = sortedLocations.last?.timestamp, last >= first {
            startDate = first
            endDate = last
        } else {
            startDate = date
            endDate = date
        }
        
        // Calculate total distance by summing distances between consecutive points
        var totalDistanceMeters: Double = 0
        if allLocations.count > 1 {
            for i in 0..<(allLocations.count - 1) {
                totalDistanceMeters += allLocations[i].distance(from: allLocations[i+1])
            }
        }
        
        return GPXWorkout(
            activityType: activityType,
            startDate: startDate,
            endDate: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalDistance: totalDistanceMeters,
            metadata: [
                "name": name,
                "source": "GPX Sample"
            ]
        )
    }
}

// Container for multiple tracks from a single GPX file
// Represents a waypoint (POI) from GPX file
struct GPXWaypoint: Equatable {
    let name: String
    let description: String?
    let coordinate: CLLocationCoordinate2D
    let elevation: Double?
    let timestamp: Date?
    let symbol: String?
    // The rest of wptType
    let comment: String?
    let source: String?
    let type: String?
    let links: [GPXLink]
    let fix: String?
    let satellites: Int?
    let hdop: Double?
    let vdop: Double?
    let pdop: Double?
    let magneticVariation: Double?
    let geoidHeight: Double?
    let ageOfDGPSData: Double?
    let dgpsId: Int?
    let extensions: [String: String]

    init(name: String, description: String?, coordinate: CLLocationCoordinate2D, elevation: Double?, timestamp: Date?, symbol: String?,
         comment: String? = nil, source: String? = nil, type: String? = nil, links: [GPXLink] = [], fix: String? = nil,
         satellites: Int? = nil, hdop: Double? = nil, vdop: Double? = nil, pdop: Double? = nil, magneticVariation: Double? = nil,
         geoidHeight: Double? = nil, ageOfDGPSData: Double? = nil, dgpsId: Int? = nil, extensions: [String: String] = [:]) {
        self.name = name; self.description = description; self.coordinate = coordinate; self.elevation = elevation
        self.timestamp = timestamp; self.symbol = symbol; self.comment = comment; self.source = source; self.type = type
        self.links = links; self.fix = fix; self.satellites = satellites; self.hdop = hdop; self.vdop = vdop; self.pdop = pdop
        self.magneticVariation = magneticVariation; self.geoidHeight = geoidHeight; self.ageOfDGPSData = ageOfDGPSData
        self.dgpsId = dgpsId; self.extensions = extensions
    }
    
    static func == (lhs: GPXWaypoint, rhs: GPXWaypoint) -> Bool {
        return lhs.name == rhs.name &&
               lhs.description == rhs.description &&
               lhs.coordinate.latitude == rhs.coordinate.latitude &&
               lhs.coordinate.longitude == rhs.coordinate.longitude &&
               lhs.elevation == rhs.elevation &&
               lhs.timestamp == rhs.timestamp &&
               lhs.symbol == rhs.symbol &&
               lhs.comment == rhs.comment && lhs.type == rhs.type && lhs.links == rhs.links
    }
}

struct GPXFile {
    let filename: String
    let tracks: [GPXTrack]
    let waypoints: [GPXWaypoint]
    let metadata: GPXMetadata
    let creator: String?          // <gpx creator="…">
    let version: String?          // <gpx version="…">, "1.1" or "1.0"
    
    init(filename: String, tracks: [GPXTrack], waypoints: [GPXWaypoint] = [], metadata: GPXMetadata = GPXMetadata(), creator: String? = nil, version: String? = nil) {
        self.filename = filename
        self.tracks = tracks
        self.waypoints = waypoints
        self.metadata = metadata
        self.creator = creator
        self.version = version
    }

    var routes: [GPXTrack] { tracks.filter { $0.isRoute } }
    
    // Get the "primary" track for backward compatibility
    var primaryTrack: GPXTrack? {
        tracks.first
    }
    
    // Get all track segments from all tracks
    var allSegments: [GPXTrackSegment] {
        tracks.flatMap { $0.segments }
    }
}

class GPXParser {
    
    static func loadSampleTracks() -> [GPXTrack] {
        var tracks: [GPXTrack] = []
        
        // Look for GPX files in the Samples directory
        let samplesDirPath = Bundle.main.bundlePath + "/Samples"
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: samplesDirPath) {
            do {
                let files = try fileManager.contentsOfDirectory(atPath: samplesDirPath)
                for file in files where file.hasSuffix(".gpx") {
                    let fileURL = URL(fileURLWithPath: samplesDirPath + "/" + file)
                    print("Loading sample from: \(fileURL.lastPathComponent)")
                    let gpxFile = parseGPXFile(at: fileURL)
                    tracks.append(contentsOf: gpxFile.tracks)
                }
            } catch {
                print("Error reading Samples directory: \(error)")
            }
        } else {
            print("Samples directory not found in bundle path")
        }
        
        // Try to find using resource URLs
        if let samplesURLs = Bundle.main.urls(forResourcesWithExtension: "gpx", subdirectory: nil) {
            print("Found \(samplesURLs.count) gpx files via Bundle.main.urls")
            for url in samplesURLs {
                print("Loading sample from: \(url.lastPathComponent)")
                let gpxFile = parseGPXFile(at: url)
                tracks.append(contentsOf: gpxFile.tracks)
            }
        }
        
        print("Loaded \(tracks.count) sample tracks from assets")
        return tracks
    }
    
    // Method to load sample waypoints from GPX files
    static func loadSampleWaypoints() -> [GPXWaypoint] {
        var waypoints: [GPXWaypoint] = []
        
        // Look for GPX files in the Samples directory
        let samplesDirPath = Bundle.main.bundlePath + "/Samples"
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: samplesDirPath) {
            do {
                let files = try fileManager.contentsOfDirectory(atPath: samplesDirPath)
                for file in files where file.hasSuffix(".gpx") {
                    let fileURL = URL(fileURLWithPath: samplesDirPath + "/" + file)
                    let gpxFile = parseGPXFile(at: fileURL)
                    waypoints.append(contentsOf: gpxFile.waypoints)
                }
            } catch {
                print("Error reading Samples directory: \(error)")
            }
        }
        
        // Try to find using resource URLs
        if let samplesURLs = Bundle.main.urls(forResourcesWithExtension: "gpx", subdirectory: nil) {
            for url in samplesURLs {
                let gpxFile = parseGPXFile(at: url)
                waypoints.append(contentsOf: gpxFile.waypoints)
            }
        }
        
        print("Loaded \(waypoints.count) sample waypoints from assets")
        return waypoints
    }    
    
    static func parseGPXFile(at url: URL) -> GPXFile {
        // First, check if we have a bookmark for this file already
        var resolvedURL = url
        var securityAccessGranted = false
        
        if let bookmarkData = UserDefaults.standard.data(forKey: "LastGPXBookmark_\(url.lastPathComponent)") {
            do {
                var isStale = false
                let storedURL = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if !isStale && storedURL.startAccessingSecurityScopedResource() {
                    print("Successfully accessed file via existing bookmark for parsing: \(storedURL)")
                    resolvedURL = storedURL
                    securityAccessGranted = true
                } else if isStale {
                    print("Bookmark for \(url.lastPathComponent) is stale, will create a new one")
                    UserDefaults.standard.removeObject(forKey: "LastGPXBookmark_\(url.lastPathComponent)")
                }
            } catch {
                print("Error resolving bookmark for parsing: \(error)")
            }
        }
        
        // If we don't have a bookmark or it failed, try direct access
        if !securityAccessGranted {
            if url.startAccessingSecurityScopedResource() {
                securityAccessGranted = true
                resolvedURL = url
                print("Successfully accessed security-scoped resource for GPX parsing: \(url)")
                
                // Create a bookmark for future use
                do {
                    let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(bookmarkData, forKey: "LastGPXBookmark_\(url.lastPathComponent)")
                    print("Created new bookmark for GPX file: \(url.lastPathComponent)")
                } catch {
                    print("Failed to create bookmark: \(error)")
                }
            }
        }
        
        // Ensure we release access when done
        defer {
            if securityAccessGranted {
                resolvedURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Try to read the data with proper error handling
        var xmlData: Data
        
        do {
            xmlData = try Data(contentsOf: resolvedURL)
        } catch {
            print("Failed to read GPX file at \(resolvedURL): \(error.localizedDescription)")
            
            // Try with file coordination as a fallback
            var fileData: Data?
            var coordError: NSError?
            
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: resolvedURL, options: [], error: &coordError) { coordURL in
                do {
                    fileData = try Data(contentsOf: coordURL)
                } catch let readError {
                    print("Coordinated read also failed: \(readError)")
                }
            }
            
            if let error = coordError {
                print("Coordination error: \(error)")
            }
            
            guard let data = fileData else {
                print("Could not read file data even with coordination")
                return GPXFile(filename: resolvedURL.lastPathComponent, tracks: [], waypoints: [])
            }
            
            xmlData = data
        }
        
        // Extract filename and parse data
        let filename = resolvedURL.deletingPathExtension().lastPathComponent
        let gpxFile = parseGPXData(xmlData, filename: filename)
        
        // Process each track to ensure it has a name
        var namedTracks: [GPXTrack] = []
        
        for (index, var track) in gpxFile.tracks.enumerated() {
            // If track has no name or empty name
            if track.name.isEmpty {
                if gpxFile.tracks.count == 1 {
                    // If only one track, use the filename
                    track.name = filename
                } else {
                    // If multiple tracks, use filename plus track number
                    track.name = "\(filename) - Track \(index + 1)"
                }
                print("Using generated name for track: \(track.name)")
            }
            namedTracks.append(track)
        }
        
        // Log parsing results
        let resultFile = GPXFile(filename: filename, tracks: namedTracks, waypoints: gpxFile.waypoints, metadata: gpxFile.metadata, creator: gpxFile.creator, version: gpxFile.version)
        print("Parsed GPX file \(filename): Found \(resultFile.tracks.count) tracks with \(resultFile.allSegments.count) segments and \(resultFile.waypoints.count) waypoints")
        
        return resultFile
    }
    
    static func parseGPXData(_ data: Data, filename: String = "") -> GPXFile {
        let parser = XMLParser(data: data)
        let delegate = GPXParserDelegate()
        parser.delegate = delegate
        
        if parser.parse() {
            // Return all parsed tracks and waypoints
            let result = GPXFile(filename: filename, tracks: delegate.tracks, waypoints: delegate.waypoints, metadata: delegate.metadata, creator: delegate.creator, version: delegate.version)
            
            // Success validation - verify we have meaningful data
            if result.tracks.isEmpty && result.waypoints.isEmpty {
                print("Warning: GPX file parsed successfully but no tracks, routes, or waypoints found")
            } else if !result.tracks.isEmpty && result.allSegments.isEmpty {
                print("Warning: GPX file has \(result.tracks.count) tracks/routes but no segments")
            } else if !result.tracks.isEmpty && result.allSegments.allSatisfy({ $0.locations.isEmpty }) {
                print("Warning: GPX file has \(result.tracks.count) tracks/routes and \(result.allSegments.count) segments, but no location points")
            }
            
            // Count how many routes were found (tracks with type "route")
            let routeCount = result.tracks.filter { $0.type.lowercased() == "route" }.count
            let trackCount = result.tracks.count - routeCount
            
            if trackCount > 0 {
                print("Found \(trackCount) tracks in GPX file")
            }
            
            if routeCount > 0 {
                print("Found \(routeCount) routes in GPX file")
            }
            
            if !result.waypoints.isEmpty {
                print("Found \(result.waypoints.count) waypoints in GPX file")
            }
            
            return result
        } else {
            // Parse failed - report diagnostic information
            if let error = parser.parserError {
                print("Failed to parse GPX data: \(error.localizedDescription)")
                print("Line: \(parser.lineNumber), Column: \(parser.columnNumber)")
            } else {
                print("Failed to parse GPX data with unknown error")
            }
            
            // Try to detect if this is even a GPX file by checking for typical XML tags
            if let xmlString = String(data: data, encoding: .utf8) {
                if !xmlString.contains("<gpx") {
                    print("Warning: File does not appear to be a GPX file (missing <gpx> tag)")
                } else if !xmlString.contains("<trk") && !xmlString.contains("<rte") && !xmlString.contains("<wpt") {
                    print("Warning: GPX file does not contain any tracks, routes, or waypoints (missing <trk>, <rte>, or <wpt> tags)")
                }
                
                // Log file size and beginning of content for diagnostics
                print("File size: \(data.count) bytes")
                let previewLength = min(100, xmlString.count)
                let preview = String(xmlString.prefix(previewLength))
                print("Content preview: \(preview)...")
            }
            
            return GPXFile(filename: filename, tracks: [], waypoints: [])
        }
    }
}

// GPX timestamps are ISO 8601. Strava, Garmin and others add fractional seconds; a few
// exporters omit the zone, which the spec says means UTC. One formatter per shape, shared.
enum GPXDate {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let zoneless: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f
    }()
    private static let zonelessFractional: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"; return f
    }()

    static func parse(_ text: String) -> Date? {
        fast(text) ?? plain.date(from: text) ?? fractional.date(from: text) ?? zoneless.date(from: text) ?? zonelessFractional.date(from: text)
    }

    // The formatters cost ~60 µs a call through ICU, which made a 16,000-point ride take a
    // second to open. This reads the shapes every GPX writer uses — yyyy-MM-ddTHH:mm:ss, an
    // optional fraction, then Z, ±HH:MM, ±HHMM or nothing (UTC) — with integer maths, and
    // leaves anything else to the formatters.
    static func fast(_ text: String) -> Date? {
        let u = Array(text.utf8)
        let n = u.count
        guard n >= 19 else { return nil }
        func num(_ at: Int, _ count: Int) -> Int? {
            guard at + count <= n else { return nil }
            var v = 0
            for k in at..<(at + count) {
                let c = u[k]
                guard c >= 48, c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            return v
        }
        guard u[4] == 45, u[7] == 45, u[10] == 84 || u[10] == 116 || u[10] == 32, u[13] == 58, u[16] == 58,
              let year = num(0, 4), let month = num(5, 2), let day = num(8, 2),
              let hour = num(11, 2), let minute = num(14, 2), let second = num(17, 2),
              (1...12).contains(month), (1...31).contains(day), hour <= 24, minute <= 59, second <= 60 else { return nil }
        var i = 19
        var fraction = 0.0
        if i < n, u[i] == 46 || u[i] == 44 {
            i += 1
            var scale = 0.1
            var digits = 0
            while i < n, u[i] >= 48, u[i] <= 57 {
                fraction += Double(u[i] - 48) * scale
                scale /= 10
                i += 1
                digits += 1
            }
            guard digits > 0 else { return nil }
        }
        var offset = 0
        if i < n {
            let c = u[i]
            if c == 90 || c == 122 {
                i += 1
            } else if c == 43 || c == 45 {
                let sign = c == 43 ? 1 : -1
                i += 1
                guard let oh = num(i, 2), oh <= 14 else { return nil }
                i += 2
                var om = 0
                if i < n, u[i] == 58 { i += 1 }
                if i < n {
                    guard let m = num(i, 2), m <= 59 else { return nil }
                    om = m
                    i += 2
                }
                offset = sign * (oh * 3600 + om * 60)
            } else {
                return nil
            }
        }
        guard i == n else { return nil }
        // Days since 1970-01-01 from the civil date (Howard Hinnant's algorithm), no calendar object
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146097 + doe - 719468
        let seconds = Double(days) * 86400 + Double(hour * 3600 + minute * 60 + second - offset) + fraction
        return Date(timeIntervalSince1970: seconds)
    }

}

// Placeholder timestamp for points without <time>; segments carry hasTimestamps = false then
let gpxMissingTimestamp = Date(timeIntervalSince1970: 0)

// A SAX parser for GPX 1.1 (and the 1.0 differences that matter), reading every element the
// schema defines: metadata, links, persons, bounds, waypoints with fix quality, routes, tracks,
// and <extensions> anywhere. Context is an element stack of local names, so a <link> inside a
// waypoint and a <link> inside a track never get confused, and prefixes (gpxtpx:, gpxx:, ns3:)
// are ignored on purpose.
class GPXParserDelegate: NSObject, XMLParserDelegate {
    // Results
    private(set) var metadata = GPXMetadata()
    private(set) var creator: String?
    private(set) var version: String?
    private var completedTracks: [GPXTrack] = []
    private var completedWaypoints: [GPXWaypoint] = []

    var tracks: [GPXTrack] { completedTracks }
    var waypoints: [GPXWaypoint] { completedWaypoints }
    var track: GPXTrack? { completedTracks.first }   // legacy single-track accessor

    // Element stack (local names) and the text of the element being read
    private var path: [String] = []
    private var text = ""

    // In-progress containers
    private struct PointBuilder {
        var lat: Double?, lon: Double?, ele: Double?, time: Date?
        var sample = SensorSample()
        var links: [GPXLink] = []
        var extra: [String: String] = [:]
    }
    private struct TrackBuilder {
        var name = "", type = "", cmt: String?, desc: String?, src: String?, number: Int?, date: Date?
        var links: [GPXLink] = []
        var extensions: [String: String] = [:]
        var segments: [GPXTrackSegment] = []
        var isRoute = false
    }
    private struct SegmentBuilder {
        var points: [CLLocation] = []
        var samples: [SensorSample] = []
        var hasEle = false, hasTime = false
    }
    private struct LinkBuilder { var href: String; var text: String?; var type: String? }
    private struct PersonBuilder { var name: String?; var email: String?; var link: GPXLink? }

    private var point: PointBuilder?
    private var trackBuilder: TrackBuilder?
    private var segment: SegmentBuilder?
    private var link: LinkBuilder?
    private var author: PersonBuilder?
    private var emailId: String?, emailDomain: String?

    private var current: String { path.last ?? "" }
    private var parent: String { path.count > 1 ? path[path.count - 2] : "" }
    private func inside(_ name: String) -> Bool { path.contains(name) }
    private var inExtensions: Bool { inside("extensions") }
    private var inPoint: Bool { point != nil }

    private static func local(_ qualified: String) -> String {
        qualified.split(separator: ":").last.map(String.init) ?? qualified
    }

    // Lat/lon are required by the schema; a point without a usable pair is skipped
    private static func coordinate(from attributes: [String: String]) -> (Double, Double)? {
        guard let a = attributes["lat"], let b = attributes["lon"], let lat = Double(a), let lon = Double(b),
              lat >= -90, lat <= 90, lon >= -180, lon <= 180 else { return nil }
        return (lat, lon)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = Self.local(elementName)
        path.append(name)
        text = ""

        switch name {
        case "gpx":
            creator = attributeDict["creator"]
            version = attributeDict["version"]
        case "trk", "rte":
            finishTrack()
            trackBuilder = TrackBuilder(isRoute: name == "rte")
            if name == "rte" { segment = SegmentBuilder() }   // a route is one implicit segment
        case "trkseg":
            segment = SegmentBuilder()
        case "trkpt", "rtept", "wpt":
            var p = PointBuilder()
            if let c = Self.coordinate(from: attributeDict) { p.lat = c.0; p.lon = c.1 }
            point = p
        case "link":
            link = LinkBuilder(href: attributeDict["href"] ?? "", text: nil, type: nil)
        case "author" where inside("metadata"):
            author = PersonBuilder()
        case "email" where inside("author"):
            emailId = attributeDict["id"]; emailDomain = attributeDict["domain"]
        case "copyright" where inside("metadata"):
            metadata.copyrightAuthor = attributeDict["author"]
        case "bounds" where inside("metadata"):
            if let a = attributeDict["minlat"], let b = attributeDict["minlon"], let c = attributeDict["maxlat"], let d = attributeDict["maxlon"],
               let minLat = Double(a), let minLon = Double(b), let maxLat = Double(c), let maxLon = Double(d) {
                metadata.bounds = GPXBounds(minLatitude: minLat, minLongitude: minLon, maxLatitude: maxLat, maxLongitude: maxLon)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = Self.local(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { path.removeLast(); text = "" }

        // ---- extension leaves: on points they become sensor fields, elsewhere a dictionary
        if inExtensions && name != "extensions" {
            guard !value.isEmpty else { return }          // container element, not a leaf
            if var p = point {
                if let v = Double(value) {
                    switch name {
                    case "hr", "heartrate", "HeartRate": p.sample.heartRate = v
                    case "cad", "cadence", "Cadence": p.sample.cadence = v
                    case "power", "PowerInWatts", "Power": p.sample.power = v
                    case "atemp", "temp", "temperature", "Temperature", "wtemp": p.sample.temperature = v
                    case "speed", "Speed": p.sample.speed = v
                    default: p.extra[name] = value
                    }
                } else {
                    p.extra[name] = value
                }
                point = p
            } else if trackBuilder != nil {
                trackBuilder!.extensions[name] = value
            } else if inside("metadata") {
                metadata.extensions[name] = value
            }
            return
        }

        // ---- link, wherever it sits
        if name == "link", var l = link {
            l.href = l.href.isEmpty ? value : l.href      // GPX 1.0 <url> style content
            let built = GPXLink(href: l.href, text: l.text, type: l.type)
            link = nil
            if var p = point { p.links.append(built); point = p }
            else if var a = author { a.link = built; author = a }
            else if trackBuilder != nil { trackBuilder!.links.append(built) }
            else if inside("metadata") { metadata.links.append(built) }
            return
        }
        if link != nil {
            if name == "text" { link!.text = value }
            if name == "type" { link!.type = value }
            return
        }

        // ---- a point
        if var p = point {
            switch name {
            case "trkpt", "rtept", "wpt":
                finishPoint(p, kind: name)
                point = nil
                return
            case "ele": p.ele = Double(value).flatMap { abs($0) < 9000 ? $0 : nil }   // 9999 / -9999 are "no data" sentinels (FME, some Garmin units)
            case "time": p.time = GPXDate.parse(value)
            case "name": p.sample.name = value
            case "cmt": p.sample.comment = value
            case "desc": p.sample.description = value
            case "src": p.sample.source = value
            case "sym": p.sample.symbol = value
            case "type": p.sample.type = value
            case "fix": p.sample.fix = value
            case "sat": p.sample.satellites = Int(value)
            case "hdop": p.sample.hdop = Double(value)
            case "vdop": p.sample.vdop = Double(value)
            case "pdop": p.sample.pdop = Double(value)
            case "magvar": p.sample.magneticVariation = Double(value)
            case "geoidheight": p.sample.geoidHeight = Double(value)
            case "ageofdgpsdata": p.sample.ageOfDGPSData = Double(value)
            case "dgpsid": p.sample.dgpsId = Int(value)
            case "url": p.links.append(GPXLink(href: value, text: nil, type: nil))          // GPX 1.0
            case "urlname": if let last = p.links.popLast() { p.links.append(GPXLink(href: last.href, text: value, type: last.type)) }
            default: break
            }
            point = p
            return
        }

        // ---- segment / track / route
        if name == "trkseg", let seg = segment {
            if !seg.points.isEmpty {
                trackBuilder?.segments.append(GPXTrackSegment(locations: seg.points, trackIndex: -1, samples: seg.samples, hasElevation: seg.hasEle, hasTimestamps: seg.hasTime))
            }
            segment = nil
            return
        }
        if trackBuilder != nil {
            switch name {
            case "trk", "rte": finishTrack()
            case "name": trackBuilder!.name = value
            case "type": trackBuilder!.type = value
            case "cmt": trackBuilder!.cmt = value
            case "desc": trackBuilder!.desc = value
            case "src": trackBuilder!.src = value
            case "number": trackBuilder!.number = Int(value)
            case "time": trackBuilder!.date = GPXDate.parse(value)
            case "url": trackBuilder!.links.append(GPXLink(href: value, text: nil, type: nil))
            case "urlname": if let last = trackBuilder!.links.popLast() { trackBuilder!.links.append(GPXLink(href: last.href, text: value, type: last.type)) }
            default: break
            }
            return
        }

        // ---- metadata (1.1) and the 1.0 header fields that sit directly under <gpx>
        if inside("metadata") || parent == "gpx" {
            switch name {
            case "name" where inside("author"): author?.name = value
            case "name": metadata.name = value
            case "desc": metadata.description = value
            case "keywords": metadata.keywords = value
            case "time": metadata.time = GPXDate.parse(value)
            case "year" where inside("copyright"): metadata.copyrightYear = value
            case "license" where inside("copyright"): metadata.copyrightLicense = value
            case "author":
                if var a = author {                               // 1.1 person
                    if let id = emailId, let domain = emailDomain { a.email = "\(id)@\(domain)" }
                    metadata.author = GPXPerson(name: a.name, email: a.email, link: a.link)
                    author = nil; emailId = nil; emailDomain = nil
                } else if !value.isEmpty {                        // 1.0 plain text
                    metadata.author = GPXPerson(name: value, email: metadata.author?.email, link: nil)
                }
            case "name" where inside("author"): author?.name = value
            case "email" where !inside("author"):                 // GPX 1.0 <email> under <gpx>
                metadata.author = GPXPerson(name: metadata.author?.name, email: value, link: nil)
            case "url": metadata.links.append(GPXLink(href: value, text: nil, type: nil))
            case "urlname": if let last = metadata.links.popLast() { metadata.links.append(GPXLink(href: last.href, text: value, type: last.type)) }
            default: break
            }
        }

        if name == "gpx" { finishTrack() }
    }

    private func finishPoint(_ p: PointBuilder, kind: String) {
        guard let lat = p.lat, let lon = p.lon else { return }
        if kind == "wpt" {
            completedWaypoints.append(GPXWaypoint(
                name: (p.sample.name?.isEmpty == false) ? p.sample.name! : "POI",
                description: p.sample.description,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                elevation: p.ele, timestamp: p.time, symbol: p.sample.symbol,
                comment: p.sample.comment, source: p.sample.source, type: p.sample.type, links: p.links, fix: p.sample.fix,
                satellites: p.sample.satellites, hdop: p.sample.hdop, vdop: p.sample.vdop, pdop: p.sample.pdop,
                magneticVariation: p.sample.magneticVariation, geoidHeight: p.sample.geoidHeight,
                ageOfDGPSData: p.sample.ageOfDGPSData, dgpsId: p.sample.dgpsId, extensions: p.extra))
            return
        }
        // trkpt / rtept → a CLLocation plus its sample; missing elevation and time are marked, never invented
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: p.ele ?? 0,
            horizontalAccuracy: p.sample.hdop.map { $0 * 5 } ?? 10,   // hdop × ~5 m is the usual rule of thumb
            verticalAccuracy: p.ele == nil ? -1 : (p.sample.vdop.map { $0 * 5 } ?? 10),
            timestamp: p.time ?? gpxMissingTimestamp
        )
        var sample = p.sample
        if !p.links.isEmpty { sample.links = p.links }
        if !p.extra.isEmpty { sample.extra = p.extra }
        segment?.points.append(location)
        segment?.samples.append(sample)
        if p.ele != nil { segment?.hasEle = true }
        if p.time != nil { segment?.hasTime = true }
    }

    private func finishTrack() {
        guard var t = trackBuilder else { return }
        if t.isRoute, let seg = segment {
            if !seg.points.isEmpty {
                // A <rtept> <time> is the point's creation stamp, not a recording: routes are never timed
                t.segments.append(GPXTrackSegment(locations: seg.points, trackIndex: -1, samples: seg.samples, hasElevation: seg.hasEle, hasTimestamps: false))
            }
            segment = nil
        }
        trackBuilder = nil
        guard !t.segments.isEmpty else { return }
        let index = completedTracks.count
        let segments = t.segments.map {
            GPXTrackSegment(locations: $0.locations, trackIndex: index, samples: $0.samples, hasElevation: $0.hasElevation, hasTimestamps: $0.hasTimestamps)
        }
        completedTracks.append(GPXTrack(
            name: t.name,
            type: t.type.isEmpty && t.isRoute ? "route" : t.type,
            date: t.date ?? metadata.time ?? segments.first?.locations.first.map { $0.timestamp == gpxMissingTimestamp ? Date() : $0.timestamp } ?? Date(),
            segments: segments,
            comment: t.cmt, description: t.desc, source: t.src, links: t.links, number: t.number, isRoute: t.isRoute, extensions: t.extensions))
    }
}
