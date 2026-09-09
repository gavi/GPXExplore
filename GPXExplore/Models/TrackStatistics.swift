import Foundation
import CoreLocation

// Everything the route card and the chart need from a set of segments, computed once.
// Distances are metres, times seconds, elevations metres, speeds m/s; views convert.
//
// Real files are messy: a segment can mix timed and untimed points, a route's <time> is a
// creation stamp, 2001 receivers logged a point a minute, watches log one a second with
// half-metre elevation jitter, and FME writes 9999 for "no elevation". Every rule below
// exists because a sample in ../samples tripped a simpler one.
struct TrackStatistics {
    struct Split: Identifiable {
        let index: Int                // 1-based split number
        let distance: Double          // metres in this split (the last one may be short)
        let movingTime: TimeInterval? // nil when the split has no timed interval
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
    let elapsedTime: TimeInterval?     // wall-clock across the timed intervals, day-long gaps excluded
    let movingTime: TimeInterval?      // timed intervals faster than pauseSpeed
    let averageSpeed: Double?          // timed distance over moving time
    let averagePace: TimeInterval?     // seconds per metre, the inverse
    let maxSpeed: Double?              // windowed speeds, median of five, so a GPS jump cannot win
    let speeds: [Double?]              // one per location: windowed speed of the interval ending there, nil when untimed

    let hasElevation: Bool
    let minElevation: Double?
    let maxElevation: Double?
    let elevationGain: Double?
    let elevationLoss: Double?

    let heartRate: (average: Double, max: Double)?
    let power: (average: Double, max: Double)?
    let cadence: (average: Double, max: Double)?   // zeros (coasting) excluded, as Garmin does
    let temperature: (min: Double, max: Double)?
    let hasRecordedSpeed: Bool

    let splits: [Split]

    // Slower than this, measured over at least speedWindow seconds, is a stop. The window
    // is what makes a one-second watch recording and a one-a-minute 2001 log agree: a
    // stationary watch drifts a metre a second, a sparse log has no jitter to smooth.
    static let pauseSpeed: Double = 0.5
    static let speedWindow: TimeInterval = 5
    // A gap longer than this between two stamps is not part of one activity (a tour stitched
    // into one segment, a stray 2010 stamp in a 2012 file); elapsed time skips it.
    static let activityGap: TimeInterval = 24 * 3600
    // Gain and loss accumulate with hysteresis: a climb counts once it exceeds this from the
    // last counted level, so second-by-second jitter never adds up (per-step thresholds do
    // the opposite and drop every real climb that comes in small steps). Barometric watch
    // files land within ~10% of Apple Health's figure at this value.
    static let elevationThreshold: Double = 1.5

    static let empty = TrackStatistics(segments: [], splitLength: 1000)

    init(segments: [GPXTrackSegment], splitLength: Double) {
        let locations = segments.flatMap { $0.locations }
        let samples = segments.flatMap { $0.samples }
        let n = locations.count
        pointCount = n
        segmentCount = segments.count

        // Which segment each point is in, and the segment boundaries in the flattened order
        var segmentOf: [Int] = []
        segmentOf.reserveCapacity(n)
        var segmentRanges: [Range<Int>] = []
        for (k, seg) in segments.enumerated() {
            segmentRanges.append(segmentOf.count..<(segmentOf.count + seg.locations.count))
            segmentOf += Array(repeating: k, count: seg.locations.count)
        }
        func sameSegment(_ i: Int, _ j: Int) -> Bool { segmentOf[i] == segmentOf[j] }

        // Per-point validity. Time: the segment must be timed and the point must carry a
        // stamp. Elevation: the segment must have some, and the point must not be a
        // placeholder (verticalAccuracy -1).
        let timeValid = segments.flatMap { seg in seg.locations.map { seg.hasTimestamps && $0.timestamp != gpxMissingTimestamp } }
        let eleValid = segments.flatMap { seg in seg.locations.map { seg.hasElevation && $0.verticalAccuracy >= 0 } }
        hasElevation = eleValid.contains(true)

        // Cumulative distance, one pass, no distance across segment boundaries
        var cumulative: [Double] = []
        cumulative.reserveCapacity(n)
        var running = 0.0
        for i in 0..<n {
            if i > 0 && sameSegment(i, i - 1) { running += locations[i].distance(from: locations[i - 1]) }
            cumulative.append(running)
        }
        cumulativeDistances = cumulative
        distance = running

        // Time. An interval is the stretch ending at point i; it counts only when both ends
        // are valid stamps in the same segment and the clock moved.
        let times = locations.map { $0.timestamp }
        func timedInterval(_ i: Int) -> Bool {
            i > 0 && sameSegment(i, i - 1) && timeValid[i] && timeValid[i - 1] && times[i] > times[i - 1]
        }
        var intervalMoving = [Bool](repeating: false, count: n)
        var timedIntervals = 0
        for i in 1..<max(1, n) where timedInterval(i) { timedIntervals += 1 }
        hasTimestamps = timedIntervals > 0

        if hasTimestamps {
            // Speed across interval i, measured over a window of at least speedWindow seconds
            // grown symmetrically around it (a single interval when the log is sparse)
            func windowSpeed(_ i: Int) -> Double {
                var a = i - 1, b = i
                while times[b].timeIntervalSince(times[a]) < TrackStatistics.speedWindow {
                    let forward = b + 1 < n && sameSegment(b + 1, i) && timeValid[b + 1] && times[b + 1] >= times[b]
                    let back = a > 0 && sameSegment(a - 1, i) && timeValid[a - 1] && times[a - 1] <= times[a]
                    if forward && (!back || b - i <= (i - 1) - a) { b += 1 } else if back { a -= 1 } else { break }
                }
                let dt = times[b].timeIntervalSince(times[a])
                return dt > 0 ? (cumulative[b] - cumulative[a]) / dt : 0
            }

            // Elapsed: successive stamps within a segment, backward jumps and day-long gaps skipped
            var validTimes: [Date] = []
            var elapsed = 0.0
            for range in segmentRanges {
                let t = range.filter { timeValid[$0] }.map { times[$0] }
                for k in 1..<max(1, t.count) {
                    let dt = t[k].timeIntervalSince(t[k - 1])
                    if dt > 0 && dt <= TrackStatistics.activityGap { elapsed += dt }
                }
                validTimes += t
            }
            startDate = validTimes.min()
            endDate = validTimes.max()
            elapsedTime = elapsed

            var moving = 0.0, timedDistance = 0.0
            var speedAt = [Double?](repeating: nil, count: n)
            for i in 1..<n where timedInterval(i) {
                let dt = times[i].timeIntervalSince(times[i - 1])
                timedDistance += cumulative[i] - cumulative[i - 1]
                let v = windowSpeed(i)
                speedAt[i] = v
                if v >= TrackStatistics.pauseSpeed {
                    moving += dt
                    intervalMoving[i] = true
                }
            }
            movingTime = moving
            averageSpeed = moving > 0 && timedDistance > 0 ? timedDistance / moving : nil
            averagePace = moving > 0 && timedDistance > 0 ? moving / timedDistance : nil
            speeds = speedAt

            // Max: a 2001 receiver logging a point a minute can jump 400 m and back, which is
            // two intervals at 30 m/s on a hike. The median of five neighbouring windowed
            // speeds drops any spike shorter than three intervals; a real sprint survives.
            var best = 0.0
            for i in 1..<n where speedAt[i] != nil {
                var neighbours: [Double] = []
                for j in max(1, i - 2)...min(n - 1, i + 2) where sameSegment(j, i) {
                    if let v = speedAt[j] { neighbours.append(v) }
                }
                neighbours.sort()
                best = max(best, neighbours[neighbours.count / 2])
            }
            maxSpeed = best > 0 ? best : nil
        } else {
            startDate = nil; endDate = nil; elapsedTime = nil; movingTime = nil
            averageSpeed = nil; averagePace = nil; maxSpeed = nil
            speeds = [Double?](repeating: nil, count: n)
        }

        // Elevation: min/max over valid points; gain/loss with hysteresis, restarted per segment
        if hasElevation {
            var lo = Double.infinity, hi = -Double.infinity
            var gain = 0.0, loss = 0.0
            var reference: Double?
            for range in segmentRanges {
                reference = nil
                for i in range where eleValid[i] {
                    let e = locations[i].altitude
                    lo = min(lo, e); hi = max(hi, e)
                    guard let r = reference else { reference = e; continue }
                    let d = e - r
                    if d >= TrackStatistics.elevationThreshold { gain += d; reference = e }
                    else if d <= -TrackStatistics.elevationThreshold { loss -= d; reference = e }
                }
            }
            minElevation = lo.isFinite ? lo : nil
            maxElevation = hi.isFinite ? hi : nil
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
        cadence = stats(samples.compactMap { $0.cadence }.filter { $0 > 0 })
        let temps = samples.compactMap { $0.temperature }
        temperature = temps.isEmpty ? nil : (temps.min() ?? 0, temps.max() ?? 0)
        hasRecordedSpeed = samples.contains { $0.speed != nil }

        // Splits: every splitLength metres of cumulative distance, moving time from the
        // same interval decisions as the headline number
        var result: [Split] = []
        if running > 0 && splitLength > 0 {
            var start = 0
            var nextBoundary = splitLength
            var i = 1
            while i < n {
                let reached = cumulative[i] >= nextBoundary
                let last = i == n - 1
                if reached || last {
                    let d = cumulative[i] - cumulative[start]
                    var t: TimeInterval?
                    if hasTimestamps {
                        var mt = 0.0
                        var timed = false
                        for j in (start + 1)...i where timedInterval(j) {
                            timed = true
                            if intervalMoving[j] { mt += times[j].timeIntervalSince(times[j - 1]) }
                        }
                        if timed { t = mt }
                    }
                    let e: Double? = (eleValid[i] && eleValid[start]) ? locations[i].altitude - locations[start].altitude : nil
                    if d > 0 { result.append(Split(index: result.count + 1, distance: d, movingTime: t, elevationChange: e)) }
                    start = i
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
