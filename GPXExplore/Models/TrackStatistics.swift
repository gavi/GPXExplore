import Foundation
import CoreLocation

// Everything the route card and the chart need from a set of segments, computed once.
// Distances are metres, times seconds, elevations metres, speeds m/s; views convert.
struct TrackStatistics {
    struct Split: Identifiable {
        let index: Int                // 1-based split number
        let distance: Double          // metres in this split (the last one may be short)
        let movingTime: TimeInterval? // nil when the file has no timestamps
        let elevationChange: Double?  // metres, end minus start; nil without elevation
        var id: Int { index }
        var pace: TimeInterval? {     // seconds per metre
            guard let t = movingTime, distance > 0 else { return nil }
            return t / distance
        }
    }

    let pointCount: Int
    let segmentCount: Int
    let distance: Double
    let cumulativeDistances: [Double]  // one per location, in flattened order; the chart's x axis

    let hasTimestamps: Bool
    let startDate: Date?
    let endDate: Date?
    let elapsedTime: TimeInterval?
    let movingTime: TimeInterval?
    let averageSpeed: Double?          // over moving time
    let maxSpeed: Double?              // 5-point smoothed
    var averagePace: TimeInterval? {   // seconds per metre
        guard let t = movingTime, distance > 0 else { return nil }
        return t / distance
    }

    let hasElevation: Bool
    let minElevation: Double?
    let maxElevation: Double?
    let elevationGain: Double?
    let elevationLoss: Double?

    let heartRate: (average: Double, max: Double)?
    let power: (average: Double, max: Double)?
    let cadence: (average: Double, max: Double)?
    let temperature: (min: Double, max: Double)?
    let hasRecordedSpeed: Bool

    let splits: [Split]

    // A stretch counts as a pause when the recorder stopped (gap over 30 s) or the
    // subject did (under 0.5 m/s across the interval). Both are excluded from moving time.
    static let pauseGap: TimeInterval = 30
    static let pauseSpeed: Double = 0.5
    // Elevation changes under a metre are GPS noise, not climbing (matches the map's rule)
    static let elevationNoise: Double = 1.0

    static let empty = TrackStatistics(segments: [], splitLength: 1000)

    init(segments: [GPXTrackSegment], splitLength: Double) {
        let locations = segments.flatMap { $0.locations }
        let samples = segments.flatMap { $0.samples }
        // Per-point validity: a file can mix timed and untimed (or with/without elevation) segments
        let timeValid = segments.flatMap { seg in Array(repeating: seg.hasTimestamps, count: seg.locations.count) }
        let eleValid = segments.flatMap { seg in seg.locations.map { seg.hasElevation && $0.verticalAccuracy >= 0 } }
        pointCount = locations.count
        segmentCount = segments.count
        hasTimestamps = timeValid.filter { $0 }.count > 1
        hasElevation = eleValid.contains(true)

        // Cumulative distance, one pass, no distance across segment boundaries
        var cumulative: [Double] = []
        cumulative.reserveCapacity(locations.count)
        var running = 0.0
        var segmentStarts = Set<Int>()
        var offset = 0
        for segment in segments { segmentStarts.insert(offset); offset += segment.locations.count }
        for (i, loc) in locations.enumerated() {
            if i > 0 && !segmentStarts.contains(i) { running += loc.distance(from: locations[i - 1]) }
            cumulative.append(running)
        }
        cumulativeDistances = cumulative
        distance = running

        // Time
        var moving = 0.0
        var speeds: [Double] = []           // instantaneous speed per interval, for the max
        if hasTimestamps {
            let times = locations.map { $0.timestamp }
            let validTimes = zip(times, timeValid).filter { $0.1 }.map { $0.0 }
            startDate = validTimes.min()
            endDate = validTimes.max()
            // Elapsed is per segment (a file with several days of tracks is not one long activity)
            var elapsed = 0.0
            for seg in segments where seg.hasTimestamps && seg.locations.count > 1 {
                let t = seg.locations.map { $0.timestamp }
                if let a = t.min(), let b = t.max() { elapsed += b.timeIntervalSince(a) }
            }
            elapsedTime = elapsed
            for i in 1..<locations.count where !segmentStarts.contains(i) && timeValid[i] && timeValid[i - 1] {
                let dt = times[i].timeIntervalSince(times[i - 1])
                let dd = cumulative[i] - cumulative[i - 1]
                guard dt > 0 else { continue }
                let v = dd / dt
                if dt <= TrackStatistics.pauseGap && v >= TrackStatistics.pauseSpeed {
                    moving += dt
                    speeds.append(v)
                }
            }
            movingTime = moving
            averageSpeed = moving > 0 ? running / moving : nil
            // Smooth over five intervals before taking the max, so a single GPS jump does not win
            if speeds.count >= 5 {
                var best = 0.0
                var window = 0.0
                for i in 0..<speeds.count {
                    window += speeds[i]
                    if i >= 5 { window -= speeds[i - 5] }
                    if i >= 4 { best = max(best, window / 5) }
                }
                maxSpeed = best
            } else {
                maxSpeed = speeds.max()
            }
        } else {
            startDate = nil; endDate = nil; elapsedTime = nil; movingTime = nil; averageSpeed = nil; maxSpeed = nil
        }

        // Elevation
        if hasElevation {
            let elevations = locations.map { $0.altitude }
            let valid = zip(elevations, eleValid).filter { $0.1 }.map { $0.0 }
            minElevation = valid.min()
            maxElevation = valid.max()
            var gain = 0.0, loss = 0.0
            for i in 1..<max(1, elevations.count) where !segmentStarts.contains(i) && eleValid[i] && eleValid[i - 1] {
                let d = elevations[i] - elevations[i - 1]
                if d > TrackStatistics.elevationNoise { gain += d } else if d < -TrackStatistics.elevationNoise { loss -= d }
            }
            elevationGain = gain
            elevationLoss = loss
        } else {
            minElevation = nil; maxElevation = nil; elevationGain = nil; elevationLoss = nil
        }

        // Sensors
        func stats(_ values: [Double]) -> (average: Double, max: Double)? {
            guard !values.isEmpty else { return nil }
            return (values.reduce(0, +) / Double(values.count), values.max() ?? 0)
        }
        heartRate = stats(samples.compactMap { $0.heartRate })
        power = stats(samples.compactMap { $0.power })
        cadence = stats(samples.compactMap { $0.cadence })
        let temps = samples.compactMap { $0.temperature }
        temperature = temps.isEmpty ? nil : (temps.min() ?? 0, temps.max() ?? 0)
        hasRecordedSpeed = samples.contains { $0.speed != nil }

        // Splits: every splitLength metres of cumulative distance
        var result: [Split] = []
        if running > 0 && splitLength > 0 {
            var splitStartIndex = 0
            var nextBoundary = splitLength
            var i = 1
            while i < locations.count {
                let reached = cumulative[i] >= nextBoundary
                let last = i == locations.count - 1
                if reached || last {
                    let end = i
                    let d = cumulative[end] - cumulative[splitStartIndex]
                    var t: TimeInterval? = nil
                    if hasTimestamps && timeValid[splitStartIndex] && timeValid[end] {
                        var mt = 0.0
                        for j in (splitStartIndex + 1)...end where !segmentStarts.contains(j) && timeValid[j] && timeValid[j - 1] {
                            let dt = locations[j].timestamp.timeIntervalSince(locations[j - 1].timestamp)
                            let dd = cumulative[j] - cumulative[j - 1]
                            if dt > 0 && dt <= TrackStatistics.pauseGap && dd / dt >= TrackStatistics.pauseSpeed { mt += dt }
                        }
                        t = mt
                    }
                    let e: Double? = (eleValid[end] && eleValid[splitStartIndex]) ? locations[end].altitude - locations[splitStartIndex].altitude : nil
                    if d > 0 { result.append(Split(index: result.count + 1, distance: d, movingTime: t, elevationChange: e)) }
                    splitStartIndex = end
                    nextBoundary += splitLength
                }
                i += 1
            }
        }
        splits = result
    }
}

// Formatting shared by the overlays, so pace, speed and durations read the same everywhere
enum StatsFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // seconds per metre → "5:12 /km" or "8:22 /mi"
    static func pace(_ secondsPerMetre: TimeInterval, metric: Bool) -> String {
        let per = secondsPerMetre * (metric ? 1000 : 1609.34)
        guard per.isFinite, per < 36000 else { return "—" }
        let m = Int(per) / 60, s = Int(per) % 60
        return String(format: "%d:%02d /%@", m, s, metric ? "km" : "mi")
    }

    // m/s → "24.3 km/h" or "15.1 mph"
    static func speed(_ metresPerSecond: Double, metric: Bool) -> String {
        let v = metric ? metresPerSecond * 3.6 : metresPerSecond * 2.23694
        return String(format: "%.1f %@", v, metric ? "km/h" : "mph")
    }

    static func elevation(_ metres: Double, metric: Bool) -> String {
        metric ? String(format: "%.0f m", metres) : String(format: "%.0f ft", metres * 3.28084)
    }

    static func distance(_ metres: Double, metric: Bool) -> String {
        metric ? String(format: "%.2f km", metres / 1000) : String(format: "%.2f mi", metres / 1609.34)
    }

    static func temperature(_ celsius: Double, metric: Bool) -> String {
        metric ? String(format: "%.0f°C", celsius) : String(format: "%.0f°F", celsius * 9 / 5 + 32)
    }
}
