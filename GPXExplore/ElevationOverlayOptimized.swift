import SwiftUI
import CoreLocation
import Charts

// Which series the chart shows. Elevation is the default; the others appear only when
// the file carries them (see TrackStatistics / SensorSample).
enum ChartMetric: String, CaseIterable, Identifiable {
    case elevation = "Elevation"
    case heartRate = "Heart rate"
    case power = "Power"
    case cadence = "Cadence"
    case speed = "Speed"
    case temperature = "Temperature"

    var id: String { rawValue }
    var title: LocalizedStringKey { LocalizedStringKey(rawValue) }

    var systemImage: String {
        switch self {
        case .elevation: return "mountain.2"
        case .heartRate: return "heart"
        case .power: return "bolt"
        case .cadence: return "arrow.triangle.2.circlepath"
        case .speed: return "speedometer"
        case .temperature: return "thermometer.medium"
        }
    }

    var color: Color {
        switch self {
        case .elevation: return .green
        case .heartRate: return TrackColors.heartRate
        case .power: return TrackColors.power
        case .cadence: return TrackColors.cadence
        case .speed: return TrackColors.speed
        case .temperature: return TrackColors.temperature
        }
    }

    // Metrics the visible segments can actually plot
    static func available(for segments: [GPXTrackSegment], stats: TrackStatistics) -> [ChartMetric] {
        var out: [ChartMetric] = []
        if stats.hasElevation { out.append(.elevation) }
        if stats.heartRate != nil { out.append(.heartRate) }
        if stats.power != nil { out.append(.power) }
        if stats.cadence != nil { out.append(.cadence) }
        if stats.hasRecordedSpeed || stats.hasTimestamps { out.append(.speed) }
        if stats.temperature != nil { out.append(.temperature) }
        return out
    }
}

struct ElevationOverlay: View {
    let trackSegments: [GPXTrackSegment]
    let stats: TrackStatistics
    @Binding var metric: ChartMetric
    @EnvironmentObject var settings: SettingsModel

    // Binding to report the currently hovered point for map marker
    @Binding var selectedPointIndex: Int?
    @Binding var zoomRange: ClosedRange<Double>?

    // False when rendering for the exported image: no title, picker or zoom controls, just the numbers and the chart
    let showsHeader: Bool

    // On a phone the panel is the picker and the chart, nothing else, and shorter
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
    #else
    private var compact: Bool { false }
    #endif

    init(trackSegments: [GPXTrackSegment], stats: TrackStatistics, metric: Binding<ChartMetric>,
         selectedPointIndex: Binding<Int?> = .constant(nil), zoomRange: Binding<ClosedRange<Double>?> = .constant(nil),
         showsHeader: Bool = true) {
        self.showsHeader = showsHeader
        self.trackSegments = trackSegments
        self.stats = stats
        self._metric = metric
        self._selectedPointIndex = selectedPointIndex
        self._zoomRange = zoomRange
    }

    // Data structure for chart points
    struct ElevationPoint: Identifiable {
        let distance: Double
        let elevation: Double     // the plotted value, in display units, whatever the metric
        let index: Int
        let originalIndex: Int    // Original index in the flattened locations array
        let segment: Int          // which segment; the chart draws one series per segment so joins are not lines
        var id: Int { index }
    }

    struct Series {
        let points: [ElevationPoint]
        let min: Double
        let max: Double
        let unit: String
    }

    private var useMetric: Bool { settings.useMetricSystem }

    // Value of the chosen metric at a flattened location index, in display units; nil = no data there
    private func value(at i: Int, locations: [CLLocation], samples: [SensorSample], eleValid: [Bool]) -> Double? {
        switch metric {
        case .elevation:
            guard eleValid[i] else { return nil }
            return useMetric ? locations[i].altitude : locations[i].altitude * 3.28084
        case .heartRate: return samples[i].heartRate
        case .power: return samples[i].power
        case .cadence: return samples[i].cadence
        case .temperature:
            guard let c = samples[i].temperature else { return nil }
            return useMetric ? c : c * 9 / 5 + 32
        case .speed:
            // recorded speed when the file has it, else the same windowed speed the statistics use
            guard let v = samples[i].speed ?? stats.speeds[i] else { return nil }
            return useMetric ? v * 3.6 : v * 2.23694
        }
    }

    private var unit: String {
        switch metric {
        case .elevation: return useMetric ? "m" : "ft"
        case .heartRate: return "bpm"
        case .power: return "W"
        case .cadence: return "rpm"
        case .speed: return useMetric ? "km/h" : "mph"
        case .temperature: return useMetric ? "°C" : "°F"
        }
    }

    // Build the series for the chart: strided, distances from the prefix sums (linear)
    private func prepareSeries() -> Series {
        let locations = trackSegments.flatMap { $0.locations }
        let samples = trackSegments.flatMap { $0.samples }
        let eleValid = trackSegments.flatMap { seg in seg.locations.map { seg.hasElevation && $0.verticalAccuracy >= 0 } }
        let distances = stats.cumulativeDistances
        guard locations.count == distances.count, samples.count == locations.count else {
            return Series(points: [], min: 0, max: 0, unit: unit)
        }
        let strideSize = calculateStrideSize(for: locations.count)
        let toDisplay = useMetric ? 1.0 / 1000.0 : 1.0 / 1609.34
        var segmentOf: [Int] = []
        segmentOf.reserveCapacity(locations.count)
        for (k, seg) in trackSegments.enumerated() { segmentOf += Array(repeating: k, count: seg.locations.count) }

        var points: [ElevationPoint] = []
        points.reserveCapacity(locations.count / strideSize + 2)
        var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
        func add(_ i: Int) {
            guard let v = value(at: i, locations: locations, samples: samples, eleValid: eleValid) else { return }
            points.append(ElevationPoint(distance: distances[i] * toDisplay, elevation: v, index: points.count, originalIndex: i, segment: segmentOf[i]))
            lo = Swift.min(lo, v); hi = Swift.max(hi, v)
        }
        for i in stride(from: 0, to: locations.count, by: strideSize) { add(i) }
        // Striding must not skip a segment's first and last point, or short segments vanish
        if strideSize > 1 {
            var offset = 0
            for seg in trackSegments {
                let first = offset, last = offset + seg.locations.count - 1
                offset += seg.locations.count
                for i in [first, last] where i >= 0 && i % strideSize != 0 && !points.contains(where: { $0.originalIndex == i }) { add(i) }
            }
            points.sort { $0.originalIndex < $1.originalIndex }
            points = points.enumerated().map { ElevationPoint(distance: $1.distance, elevation: $1.elevation, index: $0, originalIndex: $1.originalIndex, segment: $1.segment) }
        }
        if points.isEmpty { lo = 0; hi = 0 }
        return Series(points: points, min: lo, max: hi, unit: unit)
    }

    var body: some View {
        VStack {
            let series = prepareSeries()
            let available = ChartMetric.available(for: trackSegments, stats: stats)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if showsHeader {
                        HStack(spacing: 8) {
                            if !compact {
                                Text(metric == .elevation ? LocalizedStringKey("Elevation Profile") : metric.title)
                                    .font(.headline)
                            }
                            if available.count > 1 {
                                Picker("Metric", selection: $metric) {
                                    ForEach(available) { m in
                                        Label(m.title, systemImage: m.systemImage).tag(m)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .fixedSize()
                                .accessibilityLabel("Chart metric")
                            }
                        }
                        }

                        if compact && showsHeader {
                            EmptyView()
                        } else {
                        HStack(spacing: 16) {
                            if metric == .elevation, stats.hasElevation {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down").foregroundColor(.blue)
                                    Text("Min: \(StatsFormat.elevation(stats.minElevation ?? 0, metric: useMetric))").font(.caption)
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up").foregroundColor(.red)
                                    Text("Max: \(StatsFormat.elevation(stats.maxElevation ?? 0, metric: useMetric))").font(.caption)
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "mountain.2").foregroundColor(.green)
                                    Text("Gain: \(StatsFormat.elevation(stats.elevationGain ?? 0, metric: useMetric))").font(.caption)
                                }
                            } else if !series.points.isEmpty {
                                Text(String(format: "%.0f–%.0f %@", series.min, series.max, series.unit)).font(.caption)
                                if metric == .heartRate, let hr = stats.heartRate {
                                    Text("avg \(Int(hr.average.rounded())) bpm").font(.caption)
                                } else if metric == .power, let p = stats.power {
                                    Text("avg \(Int(p.average.rounded())) W").font(.caption)
                                } else if metric == .cadence, let c = stats.cadence {
                                    Text("avg \(Int(c.average.rounded())) rpm").font(.caption)
                                } else if metric == .speed, let v = stats.averageSpeed {
                                    Text("avg \(StatsFormat.speed(v, metric: useMetric))").font(.caption)
                                }
                            }
                        }
                        }
                    }

                    Spacer()

                    // Zoom indicator and reset button
                    if showsHeader, zoomRange != nil {
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                let zoomStart = String(format: "%.1f", zoomRange?.lowerBound ?? 0)
                                let zoomEnd = String(format: "%.1f", zoomRange?.upperBound ?? 0)
                                let xUnit = useMetric ? "km" : "mi"
                                Text("\(zoomStart)-\(zoomEnd)\(xUnit)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(Capsule().fill(Color.secondary.opacity(0.1)))

                            Button(action: { zoomRange = nil }) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12))
                                    .padding(5)
                                    .background(Color.secondary.opacity(0.2))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .help("Reset zoom")
                        }
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: zoomRange != nil)
                    }
                }

                if !series.points.isEmpty {
                    OptimizedElevationChartView(
                        points: series.points,
                        minValue: series.min,
                        maxValue: series.max,
                        yUnit: series.unit,
                        xUnit: useMetric ? "km" : "mi",
                        tint: metric.color,
                        isElevation: metric == .elevation,
                        onHover: { pointIndex in
                            if let point = series.points.first(where: { $0.index == pointIndex }) {
                                if self.selectedPointIndex != point.originalIndex {
                                    self.selectedPointIndex = point.originalIndex
                                }
                            } else {
                                self.selectedPointIndex = nil
                            }
                        },
                        onDragSelection: { startDistance, endDistance in
                            zoomRange = startDistance != endDistance ? startDistance...endDistance : nil
                        },
                        zoomRange: zoomRange
                    )
                    .frame(height: compact ? 96 : 120)
                    .padding(.vertical, compact ? 0 : 4)
                } else {
                    Text(metric == .elevation ? "This file has no elevation data." : "No \(metric.rawValue.lowercased()) data in the visible tracks.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(height: 40)
                }
            }
            .padding(compact ? 10 : 16)
            #if os(iOS) || os(visionOS)
            .background(Color(UIColor.systemBackground).opacity(0.8))
            #elseif os(macOS)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            #endif
            .cornerRadius(12)
            .padding(.horizontal, compact ? 10 : 16)
            .padding(.bottom, compact ? 8 : 16)
        }
    }

    // Stride so the chart draws a sensible number of points; density setting scales it
    private func calculateStrideSize(for dataPointCount: Int) -> Int {
        let strideFactor = settings.chartDataStride
        if dataPointCount <= 500 { return 1 }
        if dataPointCount <= 2000 { return settings.chartDataDensity >= 1.0 ? 1 : strideFactor }
        return max(1, dataPointCount / 2000) * strideFactor
    }
}

// The chart itself: area + line, hover/scrub marker, macOS drag-to-zoom
struct OptimizedElevationChartView: View {
    let points: [ElevationOverlay.ElevationPoint]
    let minValue: Double
    let maxValue: Double
    let yUnit: String
    let xUnit: String
    var tint: Color = .green
    var isElevation: Bool = true
    var onHover: ((Int?) -> Void)? = nil
    var onDragSelection: ((Double, Double) -> Void)? = nil
    var zoomRange: ClosedRange<Double>? = nil

    @State private var selectedPoint: ElevationOverlay.ElevationPoint? = nil
    @State private var isDragging: Bool = false
    @State private var dragStart: Double? = nil
    @State private var dragEnd: Double? = nil

    private var yScaleDomain: ClosedRange<Double> {
        let span = max(maxValue - minValue, 1)
        return (minValue - span * 0.05)...(maxValue + span * 0.05)
    }

    private var lineGradient: LinearGradient {
        isElevation
            ? LinearGradient(colors: [Color.blue, Color.green, Color.red], startPoint: .bottom, endPoint: .top)
            : LinearGradient(colors: [tint, tint], startPoint: .bottom, endPoint: .top)
    }
    private var areaGradient: LinearGradient {
        isElevation
            ? LinearGradient(colors: [Color.blue.opacity(0.3), Color.green.opacity(0.3), Color.red.opacity(0.3)], startPoint: .bottom, endPoint: .top)
            : LinearGradient(colors: [tint.opacity(0.05), tint.opacity(0.35)], startPoint: .bottom, endPoint: .top)
    }

    private func findClosestPoint(to distance: Double) -> ElevationOverlay.ElevationPoint? {
        guard let first = points.first, let last = points.last else { return nil }
        if distance <= first.distance { return first }
        if distance >= last.distance { return last }
        var low = 0
        var high = points.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if points[mid].distance < distance { low = mid } else { high = mid }
        }
        return abs(points[low].distance - distance) < abs(points[high].distance - distance) ? points[low] : points[high]
    }

    var body: some View {
        Chart {
            // One series per segment: no line or fill is drawn between the end of one segment
            // and the start of the next (they share an x, so a joined line is a vertical edge
            // and the folded fill leaves a hole)
            ForEach(points) { point in
                AreaMark(x: .value("Distance", point.distance), y: .value("Value", point.elevation),
                         series: .value("Segment", point.segment), stacking: .unstacked)
                    .foregroundStyle(areaGradient)
            }
            ForEach(points) { point in
                LineMark(x: .value("Distance", point.distance), y: .value("Value", point.elevation),
                         series: .value("Segment", point.segment))
                    .foregroundStyle(lineGradient)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let selectedPoint = selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.distance))
                    .foregroundStyle(Color.gray.opacity(0.3))
                    .zIndex(-1)
                PointMark(x: .value("Distance", selectedPoint.distance), y: .value("Value", selectedPoint.elevation))
                    .foregroundStyle(Color.white)
                    .symbolSize(150)
                PointMark(x: .value("Distance", selectedPoint.distance), y: .value("Value", selectedPoint.elevation))
                    .foregroundStyle(Color.red)
                    .symbolSize(100)
                    .annotation(position: .top, alignment: .leading) {
                        Text(String(format: "%.0f %@", selectedPoint.elevation, yUnit))
                            .font(.caption2)
                            .padding(3)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }
            }
            if isDragging, let start = dragStart, let end = dragEnd {
                RectangleMark(
                    xStart: .value("Start", min(start, end)), xEnd: .value("End", max(start, end)),
                    yStart: .value("Bottom", yScaleDomain.lowerBound), yEnd: .value("Top", yScaleDomain.upperBound)
                )
                .foregroundStyle(Color.blue.opacity(0.2))
            }
        }
        .chartYScale(domain: yScaleDomain)
        .chartXScale(domain: zoomRange ?? (points.first?.distance ?? 0)...(points.last?.distance ?? 1))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let yValue = value.as(Double.self) {
                        Text("\(Int(yValue)) \(yUnit)").font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let xValue = value.as(Double.self) {
                        Text(String(format: "%.1f \(xUnit)", xValue)).font(.caption2)
                    }
                }
            }
        }
        .accessibilityLabel("\(isElevation ? "Elevation" : "Value") profile, \(Int(minValue)) to \(Int(maxValue)) \(yUnit)")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    #if os(iOS) || os(visionOS)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if let distance = proxy.value(atX: value.location.x, as: Double.self),
                                   let closestPoint = findClosestPoint(to: distance) {
                                    selectedPoint = closestPoint
                                    onHover?(closestPoint.index)
                                }
                            }
                            .onEnded { _ in onHover?(nil) }
                    )
                    #elseif os(macOS)
                    .onHover { hovering in
                        if !hovering && !isDragging { onHover?(nil) }
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if !isDragging, let distance = proxy.value(atX: location.x, as: Double.self),
                               let closestPoint = findClosestPoint(to: distance) {
                                selectedPoint = closestPoint
                                onHover?(closestPoint.index)
                            }
                        case .ended:
                            if !isDragging { onHover?(nil) }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    dragStart = proxy.value(atX: value.startLocation.x, as: Double.self)
                                }
                                dragEnd = proxy.value(atX: value.location.x, as: Double.self)
                            }
                            .onEnded { _ in
                                if let start = dragStart, let end = dragEnd, isDragging, abs(end - start) > 0.05 {
                                    onDragSelection?(min(start, end), max(start, end))
                                }
                                isDragging = false
                                dragStart = nil
                                dragEnd = nil
                            }
                    )
                    #endif
            }
        }
        .gesture(TapGesture(count: 2).onEnded { onDragSelection?(0, 0) })
    }
}
