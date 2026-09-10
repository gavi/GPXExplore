import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @Binding var document: GPXExploreDocument
    @StateObject private var settings = SettingsModel()
    @State private var isTracksDrawerOpen = false

    // Phone layout: the drawer is a sheet, not a side panel, and the bar shows the
    // buttons rather than the file name (the name is on the route card)
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
    #else
    private var compact: Bool { false }
    #endif
    @State private var isSettingsPresented = false
    @State private var visibleSegments: [Bool] = []
    @State private var selectedTrackIndex: Int = 0
    @State private var segments: [GPXTrackSegment] = []
    @State private var waypointsVisible: Bool = true
    @State private var documentTitle: String = "GPX Explore"
    @State private var selectedWaypointIndex: Int = -1 // -1 indicates no selection
    @State private var selectedWaypointCoordinate: CLLocationCoordinate2D? = nil
    @State private var triggerSpanView: Bool = false
    @State private var isElevationOverlayVisible: Bool = false
    @State private var isRouteInfoOverlayVisible: Bool = true
    @State private var chartHoverPointIndex: Int? = nil // Index in trackLocations for chart hover
    @State private var chartZoomRange: ClosedRange<Double>? = nil // Current zoom range for chart
    @State private var chartMetric: ChartMetric = .elevation

    // Statistics for the visible segments, recomputed only when they change (never in body)
    @State private var stats: TrackStatistics = .empty

    // Export
    @State private var isExporting = false
    @State private var exportedImageURL: URL? = nil
    @State private var exportError: String? = nil
    @Environment(\.documentConfiguration) private var documentConfiguration

    private func updateDocumentTitle() {
        if let filename = document.gpxFile?.filename {
            documentTitle = (filename as NSString).deletingPathExtension
        } else {
            documentTitle = "GPX Explore"
        }
    }

    private func updateFromDocument() {
        segments = document.trackSegments
        if visibleSegments.count != segments.count {
            visibleSegments = Array(repeating: true, count: segments.count)
        }
        recomputeStats()
    }

    private func recomputeStats() {
        let visible = visibleTrackSegments
        stats = TrackStatistics(segments: visible, splitLength: settings.useMetricSystem ? 1000 : 1609.34)
        let available = ChartMetric.available(for: visible, stats: stats)
        if !available.contains(chartMetric) { chartMetric = available.first ?? .elevation }
    }

    private var visibleTrackSegments: [GPXTrackSegment] {
        zip(segments, visibleSegments).filter { $0.1 }.map { $0.0 }
    }

    private var selectedTrack: GPXTrack? {
        guard !document.tracks.isEmpty else { return nil }
        return document.tracks.indices.contains(selectedTrackIndex) ? document.tracks[selectedTrackIndex] : document.tracks.first
    }

    private var hasContent: Bool { !document.trackSegments.isEmpty || !document.waypoints.isEmpty }

    var body: some View {
        ZStack {
            if hasContent {
                Color.clear
                    .onAppear {
                        updateFromDocument()
                        isElevationOverlayVisible = settings.defaultShowElevationOverlay
                        isRouteInfoOverlayVisible = settings.defaultShowRouteInfoOverlay
                        // The series chosen last time, when this file has it; the drawer flag is
                        // for the screenshot script (-showTracksDrawer YES)
                        if let saved = UserDefaults.standard.string(forKey: "chartMetric"), let m = ChartMetric(rawValue: saved),
                           ChartMetric.available(for: visibleTrackSegments, stats: stats).contains(m) {
                            chartMetric = m
                        }
                        if UserDefaults.standard.bool(forKey: "showTracksDrawer") { isTracksDrawerOpen = true }
                    }
                    .onChange(of: chartMetric) { _, new in UserDefaults.standard.set(new.rawValue, forKey: "chartMetric") }
                    .onChange(of: document.trackSegments.count) { _, _ in updateFromDocument() }
                    .onChange(of: visibleSegments) { _, _ in recomputeStats() }
                    .onChange(of: settings.useMetricSystem) { _, _ in recomputeStats() }

                HStack(spacing: 0) {
                    ZStack {
                        MapView(
                            trackSegments: visibleTrackSegments,
                            waypoints: waypointsVisible ? document.waypoints : [],
                            centerCoordinate: selectedWaypointCoordinate,
                            zoomLevel: 0.005,
                            spanAll: triggerSpanView,
                            hoveredPointIndex: chartHoverPointIndex
                        )
                        .environmentObject(settings)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: triggerSpanView) { _, newValue in
                            if newValue {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { triggerSpanView = false }
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WaypointSelected"))) { _ in
                            chartHoverPointIndex = nil
                            chartZoomRange = nil
                        }

                        if !visibleTrackSegments.isEmpty {
                            VStack {
                                if isRouteInfoOverlayVisible {
                                    RouteInfoOverlay(stats: stats, trackName: selectedTrack?.name ?? documentTitle, trackDescription: selectedTrack?.description ?? selectedTrack?.comment ?? document.gpxFile?.metadata.description)
                                        .environmentObject(settings)
                                        .transition(.move(edge: .top))
                                        .animation(.easeInOut, value: isRouteInfoOverlayVisible)
                                }

                                Spacer()

                                if isElevationOverlayVisible {
                                    ElevationOverlay(
                                        trackSegments: visibleTrackSegments,
                                        stats: stats,
                                        metric: $chartMetric,
                                        selectedPointIndex: $chartHoverPointIndex,
                                        zoomRange: $chartZoomRange
                                    )
                                    .environmentObject(settings)
                                    .transition(.move(edge: .bottom))
                                    .animation(.easeInOut, value: isElevationOverlayVisible)
                                }
                            }
                        } else if !document.waypoints.isEmpty {
                            VStack {
                                Text("\(document.waypoints.count) waypoint\(document.waypoints.count == 1 ? "" : "s"), no tracks")
                                    .font(.subheadline)
                                    .padding(8)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                    .padding(.top)
                                Spacer()
                            }
                        }

                        if isExporting {
                            ProgressView("Rendering image…")
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    #if os(iOS) || os(visionOS)
                    .toolbar(.visible, for: .navigationBar)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Menu {
                                ForEach(Array(MapStyle.allCases.enumerated()), id: \.element.id) { index, style in
                                    Button {
                                        settings.mapStyle = style
                                    } label: {
                                        Label(style.rawValue, systemImage: style.iconName)
                                    }
                                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                                }
                            } label: {
                                Label("Map Style", systemImage: "map")
                            }
                        }

                        ToolbarItem(placement: .automatic) {
                            Button(action: { isElevationOverlayVisible.toggle() }) {
                                Label("Elevation", systemImage: "mountain.2")
                            }
                            .keyboardShortcut("e", modifiers: .command)
                            .help("Show or hide the chart (⌘E)")
                        }

                        ToolbarItem(placement: .automatic) {
                            Button(action: { isRouteInfoOverlayVisible.toggle() }) {
                                Label("Route Info", systemImage: "info.circle")
                            }
                            .keyboardShortcut("i", modifiers: .command)
                            .help("Show or hide the route card (⌘I)")
                        }

                        // Share and export
                        ToolbarItem(placement: .automatic) {
                            Menu {
                                if let fileURL = documentFileURL {
                                    ShareLink(item: fileURL) {
                                        Label("Share GPX File", systemImage: "doc")
                                    }
                                }
                                Button {
                                    Task { await exportImage() }
                                } label: {
                                    Label("Export Map Image…", systemImage: "photo")
                                }
                                .disabled(visibleTrackSegments.isEmpty || isExporting)
                                .keyboardShortcut("e", modifiers: [.command, .shift])
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }

                        ToolbarItem(placement: .automatic) {
                            Button(action: { isSettingsPresented = true }) {
                                Label("Settings", systemImage: "gear")
                            }
                            .keyboardShortcut(",", modifiers: .command)
                        }

                        ToolbarItem(placement: .automatic) {
                            Button(action: {
                                selectedWaypointCoordinate = nil
                                triggerSpanView = true
                            }) {
                                Label("Fit to View", systemImage: "arrow.up.left.and.arrow.down.right")
                            }
                            .keyboardShortcut("0", modifiers: .command)
                            .help("Fit the track in the window (⌘0)")
                        }

                        ToolbarItem(placement: .automatic) {
                            TracksDrawer.toolbarButton(isOpen: $isTracksDrawerOpen)
                        }
                    }
                    .sheet(isPresented: $isSettingsPresented) {
                        NavigationStack {
                            SettingsView()
                                .environmentObject(settings)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { isSettingsPresented = false }
                                    }
                                }
                        }
                    }
                    .sheet(item: $exportedImageURL) { url in
                        ExportSheet(imageURL: url) { exportedImageURL = nil }
                    }
                    .alert("Could not export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(exportError ?? "")
                    }

                    if isTracksDrawerOpen && !compact {
                        tracksDrawer
                        .transition(.move(edge: .trailing))
                    }
                }
            } else {
                VStack {
                    Text("No valid GPX data found")
                        .font(.title)
                        .padding()
                    Text("This file has no tracks, routes or waypoints. Open a GPX file to view it on the map.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        #if os(iOS)
        .navigationTitle(compact ? "" : documentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { compact && isTracksDrawerOpen }, set: { isTracksDrawerOpen = $0 })) {
            tracksDrawer
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        #elseif os(macOS)
        .background(MacWindowSizer().frame(width: 0, height: 0))
        #endif
        .onAppear {
            updateDocumentTitle()
            updateFromDocument()
        }
        .onChange(of: document.gpxFile?.filename) { _, _ in updateDocumentTitle() }
    }

    private var tracksDrawer: some View {
        TracksDrawer(
            isOpen: $isTracksDrawerOpen,
            document: $document,
            visibleSegments: $visibleSegments,
            selectedTrackIndex: $selectedTrackIndex,
            segments: $segments,
            waypointsVisible: $waypointsVisible,
            selectedWaypointIndex: $selectedWaypointIndex,
            onWaypointSelected: { coordinate in
                selectedWaypointCoordinate = coordinate
                NotificationCenter.default.post(name: Notification.Name("WaypointSelected"), object: nil)
            }
        )
        .environmentObject(settings)
    }

    // The file behind this document, for sharing; falls back to a temp copy of the text
    private var documentFileURL: URL? {
        if let url = documentConfiguration?.fileURL { return url }
        guard !document.text.isEmpty else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(documentTitle).gpx")
        try? document.text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    private func exportImage() async {
        isExporting = true
        defer { isExporting = false }
        let segmentsToDraw = visibleTrackSegments
        let wantsChart = stats.hasElevation || stats.heartRate != nil || stats.hasTimestamps
        let chartImage: CGImage? = wantsChart
            ? MapImageExporter.renderChart(ElevationOverlay(trackSegments: segmentsToDraw, stats: stats, metric: .constant(chartMetric), showsHeader: false).environmentObject(settings), width: 800, height: 160)
            : nil
        var subtitle = StatsFormat.distance(stats.distance, metric: settings.useMetricSystem)
        if let moving = stats.movingTime { subtitle += "  ·  \(StatsFormat.duration(moving)) moving" }
        if let gain = stats.elevationGain { subtitle += "  ·  +\(StatsFormat.elevation(gain, metric: settings.useMetricSystem))" }
        if let start = stats.startDate { subtitle += "  ·  \(start.formatted(date: .abbreviated, time: .shortened))" }
        let options = MapImageExporter.Options(
            mapStyle: settings.mapStyle,
            visualization: settings.elevationVisualizationMode,
            lineWidth: CGFloat(settings.trackLineWidth),
            title: selectedTrack?.name ?? documentTitle,
            subtitle: subtitle
        )
        do {
            exportedImageURL = try await MapImageExporter.export(segments: segmentsToDraw, stats: stats, chartImage: chartImage, options: options)
        } catch {
            exportError = "The map could not be rendered. \(error.localizedDescription)"
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

#Preview {
    ContentView(document: .constant(GPXExploreDocument()))
}
