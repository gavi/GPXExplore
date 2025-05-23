import SwiftUI
import CoreLocation
import Charts

struct ElevationOverlay: View {
    let trackSegments: [GPXTrackSegment]
    @EnvironmentObject var settings: SettingsModel
    
    // Binding to report the currently hovered point for map marker
    @Binding var selectedPointIndex: Int?
    @Binding var zoomRange: ClosedRange<Double>?
    
    // Default initializer with optional binding for hover point
    init(trackSegments: [GPXTrackSegment], selectedPointIndex: Binding<Int?> = .constant(nil), zoomRange: Binding<ClosedRange<Double>?> = .constant(nil)) {
        self.trackSegments = trackSegments
        self._selectedPointIndex = selectedPointIndex
        self._zoomRange = zoomRange
    }
    
    // Data structure for chart points
    struct ElevationPoint: Identifiable {
        let distance: Double
        let elevation: Double
        let index: Int
        let originalIndex: Int // Original index in the locations array
        
        var id: Int { index }
    }
    
    // Get the converted elevation data for display
    private func prepareElevationData() -> (points: [ElevationPoint], min: Double, max: Double, gain: Double, locations: [CLLocation]) {
        let locations = trackSegments.flatMap { $0.locations }
        let rawElevations = locations.map { $0.altitude }
        
        // Calculate min, max and gain
        let minElevation = rawElevations.min() ?? 0
        let maxElevation = rawElevations.max() ?? 0
        let elevationGain = calculateElevationGain(rawElevations)
        
        // Calculate display elevations with unit conversion if needed
        var chartPoints: [ElevationPoint] = []
        
        // Use the chart data density setting to determine stride size
        let strideSize = calculateStrideSize(for: rawElevations.count)
        
        for (i, originalIndex) in stride(from: 0, to: rawElevations.count, by: strideSize).enumerated() {
            let elevation = rawElevations[originalIndex]
            let distanceMeters = calculateDistance(upTo: originalIndex, locations: locations)
            
            // Convert to proper units (kilometers or miles)
            let displayDistance = settings.useMetricSystem
                ? distanceMeters / 1000  // to kilometers
                : distanceMeters / 1609.34  // to miles
            
            // Convert elevation if needed
            let displayElevation = settings.useMetricSystem
                ? elevation  // keep as meters
                : elevation * 3.28084  // to feet
            
            chartPoints.append(ElevationPoint(
                distance: displayDistance,
                elevation: displayElevation,
                index: i,
                originalIndex: originalIndex
            ))
        }
        
        // Always include the last point if we're striding
        if strideSize > 1 && !chartPoints.isEmpty && chartPoints.last?.originalIndex != rawElevations.count - 1 {
            let originalIndex = rawElevations.count - 1
            let elevation = rawElevations[originalIndex]
            let distanceMeters = calculateDistance(upTo: originalIndex, locations: locations)
            
            let displayDistance = settings.useMetricSystem
                ? distanceMeters / 1000
                : distanceMeters / 1609.34
            
            let displayElevation = settings.useMetricSystem
                ? elevation
                : elevation * 3.28084
            
            chartPoints.append(ElevationPoint(
                distance: displayDistance,
                elevation: displayElevation,
                index: chartPoints.count,
                originalIndex: originalIndex
            ))
        }
        
        return (points: chartPoints, min: minElevation, max: maxElevation, gain: elevationGain, locations: locations)
    }
    
    // Calculate cumulative distance up to a specific index
    private func calculateDistance(upTo index: Int, locations: [CLLocation]) -> Double {
        guard index > 0 && index < locations.count else { return 0 }
        
        var totalDistance: Double = 0
        for i in 1...index {
            totalDistance += locations[i-1].distance(from: locations[i])
        }
        
        return totalDistance
    }
    
    var body: some View {
        VStack {
            // Get all elevation data first to simplify view code
            let elevationData = prepareElevationData()
            
            // Elevation chart with metrics
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Elevation Profile")
                            .font(.headline)

                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .foregroundColor(.blue)
                                Text("Min: \(formatElevation(elevationData.min))")
                                    .font(.caption)
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .foregroundColor(.red)
                                Text("Max: \(formatElevation(elevationData.max))")
                                    .font(.caption)
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "mountain.2")
                                    .foregroundColor(.green)
                                Text("Gain: \(formatElevation(elevationData.gain))")
                                    .font(.caption)
                            }
                        }
                    }

                    Spacer()

                    // Zoom indicator and reset button
                    if zoomRange != nil {
                        HStack(spacing: 6) {
                            // Zoom status indicator
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)

                                let zoomStart = String(format: "%.1f", zoomRange?.lowerBound ?? 0)
                                let zoomEnd = String(format: "%.1f", zoomRange?.upperBound ?? 0)
                                let unit = settings.useMetricSystem ? "km" : "mi"

                                Text("\(zoomStart)-\(zoomEnd)\(unit)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.1))
                            )

                            // Zoom out button
                            Button(action: {
                                // Reset zoom range to nil
                                zoomRange = nil
                            }) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12))
                                    .padding(5)
                                    .background(Color.secondary.opacity(0.2))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: zoomRange != nil)
                        .help("Reset zoom")
                    }
                }
                
                // Elevation chart using Swift Charts
                if !elevationData.points.isEmpty {
                    // Define common values
                    let yUnit = settings.useMetricSystem ? "m" : "ft"
                    let xUnit = settings.useMetricSystem ? "km" : "mi"
                    
                    // Create chart with interactions
                    OptimizedElevationChartView(
                        points: elevationData.points,
                        minValue: elevationData.min * (settings.useMetricSystem ? 1.0 : 3.28084),
                        maxValue: elevationData.max * (settings.useMetricSystem ? 1.0 : 3.28084),
                        yUnit: yUnit,
                        xUnit: xUnit,
                        onHover: { pointIndex in
                            // Throttle hover updates to prevent excessive map marker updates
                            // Only update if we have a point and it's different from current selection
                            if let point = elevationData.points.first(where: { $0.index == pointIndex }) {
                                // Only update if index actually changed to reduce map updates
                                if self.selectedPointIndex != point.originalIndex {
                                    self.selectedPointIndex = point.originalIndex
                                }
                            } else {
                                self.selectedPointIndex = nil
                            }
                        },
                        onDragSelection: { startDistance, endDistance in
                            if startDistance != endDistance {
                                zoomRange = startDistance...endDistance
                            } else {
                                zoomRange = nil
                            }
                        },
                        zoomRange: zoomRange
                    )
                    .frame(height: 120)
                    .padding(.vertical, 4)
                }
            }
            .padding()
            #if os(iOS) || os(visionOS)
            .background(Color(UIColor.systemBackground).opacity(0.8))
            #elseif os(macOS)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            #endif
            .cornerRadius(12)
            .padding([.horizontal, .bottom])
        }
    }
    
    // Helper function to calculate elevation gain from a series of elevation points
    private func calculateElevationGain(_ elevations: [Double]) -> Double {
        guard elevations.count > 1 else { return 0 }
        
        var gain: Double = 0
        
        for i in 1..<elevations.count {
            let diff = elevations[i] - elevations[i-1]
            // Only count positive elevation changes (uphill)
            if diff > 0 {
                gain += diff
            }
        }
        
        return gain
    }
    
    // Helper function to format elevation
    private func formatElevation(_ elevation: Double) -> String {
        if settings.useMetricSystem {
            return String(format: "%.0f m", elevation)
        } else {
            let feet = elevation * 3.28084
            return String(format: "%.0f ft", feet)
        }
    }
    
    // Helper function to calculate appropriate stride size based on settings
    private func calculateStrideSize(for dataPointCount: Int) -> Int {
        // Get the stride factor from settings
        let strideFactor = settings.chartDataStride
        
        // For small datasets, don't stride at all
        if dataPointCount <= 500 {
            return 1
        }
        
        // For medium datasets, use moderate stride if density is not maximum
        if dataPointCount <= 2000 {
            return settings.chartDataDensity >= 1.0 ? 1 : strideFactor
        }
        
        // For very large datasets, calculate a dynamic stride to get a reasonable number of points
        // Min points: dataPointCount / (strideFactor * 10)
        // Max points: dataPointCount / strideFactor
        let baseStride = max(1, dataPointCount / 2000) * strideFactor
        return baseStride
    }
}

// Extract chart into a separate view component to reduce complexity
struct OptimizedElevationChartView: View {
    let points: [ElevationOverlay.ElevationPoint]
    let minValue: Double
    let maxValue: Double
    let yUnit: String
    let xUnit: String
    var onHover: ((Int?) -> Void)? = nil
    var onDragSelection: ((Double, Double) -> Void)? = nil
    var zoomRange: ClosedRange<Double>? = nil

    // State for chart selection and interaction
    @State private var selectedDistance: Double? = nil
    @State private var isDragging: Bool = false
    @State private var dragStart: Double? = nil
    @State private var dragEnd: Double? = nil
    
    // Debounced hover state
    @State private var pendingHoverIndex: Int? = nil
    @State private var hoverDebounceTimer: Timer? = nil

    // Get y scale domain
    private var yScaleDomain: ClosedRange<Double> {
        (minValue * 0.95)...(maxValue * 1.05)
    }
    
    // Precompute data for efficient rendering
    private var chartData: (lineData: [(x: Double, y: Double, originalIndex: Int)], areaPath: Path) {
        // For very large datasets, use a simplified representation
        let useSimplified = points.count > 1000
        let step = useSimplified ? max(1, points.count / 500) : 1
        
        var linePoints: [(x: Double, y: Double, originalIndex: Int)] = []
        linePoints.reserveCapacity(points.count / step + 1)
        
        for i in stride(from: 0, to: points.count, by: step) {
            linePoints.append((x: points[i].distance, y: points[i].elevation, originalIndex: i))
        }
        
        // Always include the last point
        if !points.isEmpty && (points.count - 1) % step != 0 {
            let last = points.last!
            linePoints.append((x: last.distance, y: last.elevation, originalIndex: points.count - 1))
        }
        
        // Create area path for fill
        var path = Path()
        if !linePoints.isEmpty {
            path.move(to: CGPoint(x: linePoints[0].x, y: minValue * 0.95))
            for point in linePoints {
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            }
            if let last = linePoints.last {
                path.addLine(to: CGPoint(x: last.x, y: minValue * 0.95))
            }
            path.closeSubpath()
        }
        
        return (linePoints, path)
    }

    // Optimized binary search with caching
    private func findClosestPoint(to distance: Double) -> (point: ElevationOverlay.ElevationPoint, index: Int)? {
        guard !points.isEmpty else { return nil }
        
        // Edge cases
        if points.count == 1 { return (points[0], 0) }
        if distance <= points.first!.distance { return (points.first!, 0) }
        if distance >= points.last!.distance { return (points.last!, points.last!.index) }
        
        // Binary search
        var left = 0
        var right = points.count - 1
        
        while left < right - 1 {
            let mid = (left + right) / 2
            if points[mid].distance < distance {
                left = mid
            } else {
                right = mid
            }
        }
        
        // Find closest point
        let leftDist = abs(points[left].distance - distance)
        let rightDist = abs(points[right].distance - distance)
        
        return leftDist < rightDist ? (points[left], left) : (points[right], right)
    }
    
    // Debounced hover handler
    private func handleHover(_ index: Int?) {
        // Cancel existing timer
        hoverDebounceTimer?.invalidate()
        
        // For nil (hover end), update immediately
        if index == nil {
            onHover?(nil)
            pendingHoverIndex = nil
            return
        }
        
        // For hover updates, debounce
        pendingHoverIndex = index
        hoverDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
            if let pending = pendingHoverIndex {
                onHover?(pending)
            }
        }
    }

    // Add this function before the body property
    private func interpolateElevation(for distance: Double, in lineData: [(x: Double, y: Double, originalIndex: Int)]) -> Double {
        guard lineData.count > 1 else {
            return findClosestPoint(to: distance)?.point.elevation ?? 0
        }
        
        var leftPoint: (x: Double, y: Double, originalIndex: Int)? = nil
        var rightPoint: (x: Double, y: Double, originalIndex: Int)? = nil
        
        for i in 0..<lineData.count {
            if lineData[i].x <= distance {
                leftPoint = lineData[i]
            }
            if lineData[i].x >= distance && rightPoint == nil {
                rightPoint = lineData[i]
                break
            }
        }
        
        if let left = leftPoint, let right = rightPoint, left.x != right.x {
            let ratio = (distance - left.x) / (right.x - left.x)
            return left.y + (right.y - left.y) * ratio
        } else if let left = leftPoint {
            return left.y
        } else if let right = rightPoint {
            return right.y
        } else {
            return findClosestPoint(to: distance)?.point.elevation ?? 0
        }
    }

    var body: some View {
        let data = chartData
        
        Chart {
            // Use a single LineMark with all points instead of ForEach
            // This is MUCH more efficient for large datasets
            LineMark(
                x: .value("Distance", 0),
                y: .value("Elevation", 0),
                series: .value("Series", "elevation")
            )
            .foregroundStyle(.clear) // Invisible mark to establish chart
            
            // Highlight selected point with a marker
            if let distance = selectedDistance,
               let (selectedPoint, _) = findClosestPoint(to: distance) {
                
                // Selection indicator rule
                RuleMark(
                    x: .value("Selected", selectedPoint.distance)
                )
                .foregroundStyle(Color.gray.opacity(0.3))
                .zIndex(-1)
            }

            // Show drag selection area
            if isDragging, let start = dragStart, let end = dragEnd {
                RectangleMark(
                    xStart: .value("Start", min(start, end)),
                    xEnd: .value("End", max(start, end)),
                    yStart: .value("Bottom", minValue * 0.95),
                    yEnd: .value("Top", maxValue * 1.05)
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
                        Text("\(Int(yValue)) \(yUnit)")
                            .font(.caption2)
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
                        Text(String(format: "%.1f \(xUnit)", xValue))
                            .font(.caption2)
                    }
                }
            }
        }
        // Custom background to render the elevation profile efficiently
        .chartBackground { chartProxy in
            GeometryReader { geometry in
                // Convert chart coordinates to view coordinates
                let xScale = { (distance: Double) -> CGFloat in
                    let xRange = zoomRange ?? (points.first?.distance ?? 0)...(points.last?.distance ?? 1)
                    let normalized = (distance - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound)
                    return geometry.size.width * CGFloat(normalized)
                }
                
                let yScale = { (elevation: Double) -> CGFloat in
                    let normalized = (elevation - yScaleDomain.lowerBound) / (yScaleDomain.upperBound - yScaleDomain.lowerBound)
                    return geometry.size.height * (1.0 - CGFloat(normalized))
                }
                
                // Draw area fill
                Path { path in
                    guard !data.lineData.isEmpty else { return }
                    
                    path.move(to: CGPoint(x: xScale(data.lineData[0].x), y: yScale(minValue * 0.95)))
                    for point in data.lineData {
                        path.addLine(to: CGPoint(x: xScale(point.x), y: yScale(point.y)))
                    }
                    if let last = data.lineData.last {
                        path.addLine(to: CGPoint(x: xScale(last.x), y: yScale(minValue * 0.95)))
                    }
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.3),
                            Color.green.opacity(0.3),
                            Color.red.opacity(0.3)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                
                // Draw line
                Path { path in
                    guard !data.lineData.isEmpty else { return }
                    
                    path.move(to: CGPoint(x: xScale(data.lineData[0].x), y: yScale(data.lineData[0].y)))
                    for point in data.lineData.dropFirst() {
                        path.addLine(to: CGPoint(x: xScale(point.x), y: yScale(point.y)))
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [Color.blue, Color.green, Color.red],
                        startPoint: .bottom,
                        endPoint: .top
                    ),
                    lineWidth: 2
                )
                
                // Draw hover point directly on the line
                if let distance = selectedDistance,
                   let (selectedPoint, _) = findClosestPoint(to: distance) {
                    
                    // For simplified line data, find the actual elevation at this distance
                    // by interpolating between the nearest line segments
                    let xPos = xScale(selectedPoint.distance)
                    
                    let actualElevation = interpolateElevation(for: selectedPoint.distance, in: data.lineData)
                    let yPos = yScale(actualElevation)
                    
                    // Outer white circle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .position(x: xPos, y: yPos)
                    
                    // Inner red circle
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .position(x: xPos, y: yPos)
                }
            }
        }
        // Use chart overlay for interactions
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    #if os(iOS) || os(visionOS)
                    // iOS - Only use tap/hover with no drag zoom at all
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                selectedDistance = nil

                                // Use drag location for hover effect
                                if let distance = proxy.value(atX: value.location.x, as: Double.self),
                                   let (point, _) = findClosestPoint(to: distance) {
                                    selectedDistance = point.distance
                                    handleHover(point.index)
                                }
                            }
                            .onEnded { _ in
                                handleHover(nil)
                            }
                    )
                    #elseif os(macOS)
                    // macOS hover handling
                    .onHover { hovering in
                        if !hovering && !isDragging {
                            handleHover(nil)
                        }
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if !isDragging {
                                if let distance = proxy.value(atX: location.x, as: Double.self),
                                   let (point, _) = findClosestPoint(to: distance) {
                                    selectedDistance = point.distance
                                    handleHover(point.index)
                                }
                            }
                        case .ended:
                            if !isDragging {
                                handleHover(nil)
                            }
                        }
                    }
                    // Add combined drag gesture for direct selection
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
                                if let start = dragStart, let end = dragEnd, isDragging {
                                    if abs(end - start) > 0.05 {
                                        onDragSelection?(
                                            min(start, end),
                                            max(start, end)
                                        )
                                    }
                                }
                                isDragging = false
                                dragStart = nil
                                dragEnd = nil
                            }
                    )
                    #endif
            }
        }
        // Double tap/click to reset zoom
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    onDragSelection?(0, 0)
                }
        )
        .onDisappear {
            // Clean up timer when view disappears
            hoverDebounceTimer?.invalidate()
        }
    }
}
