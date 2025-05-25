import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @Binding var document: GPXExploreDocument
    @StateObject private var settings = SettingsModel()
    @State private var isTracksDrawerOpen = false
    @State private var isSettingsPresented = false
    @State private var visibleSegments: [Bool] = []
    @State private var selectedTrackIndex: Int = 0
    @State private var segments: [GPXTrackSegment] = []
    @State private var waypointsVisible: Bool = true
    @State private var documentTitle: String = "GPX Explorer"
    @State private var selectedWaypointIndex: Int = -1 // -1 indicates no selection
    @State private var selectedWaypointCoordinate: CLLocationCoordinate2D? = nil
    @State private var triggerSpanView: Bool = false
    @State private var isElevationOverlayVisible: Bool = false
    @State private var isRouteInfoOverlayVisible: Bool = true
    @State private var chartHoverPointIndex: Int? = nil // Index in trackLocations for chart hover
    @State private var chartZoomRange: ClosedRange<Double>? = nil // Current zoom range for chart
        
    private func updateDocumentTitle() {
        // Update title based on the GPX filename
        if let filename = document.gpxFile?.filename {
            let fileNameWithoutExtension = (filename as NSString).deletingPathExtension
            documentTitle = fileNameWithoutExtension

        } else {
            documentTitle = "GPX Explorer"
        }
    }

    private func updateFromDocument() {
        segments = document.trackSegments
        if visibleSegments.count != segments.count {
            visibleSegments = Array(repeating: true, count: segments.count)
        }
    }
    
    private var visibleTrackSegments: [GPXTrackSegment] {
        // Filter segments based on visibility
        return zip(segments, visibleSegments)
            .filter { $0.1 }  // Keep only visible segments
            .map { $0.0 }     // Return just the segment
    }
    
    private var selectedTrack: GPXTrack? {
        guard !document.tracks.isEmpty else { return nil }
        if document.tracks.indices.contains(selectedTrackIndex) {
            return document.tracks[selectedTrackIndex]
        } else {
            // Reset to first track if index is invalid
            selectedTrackIndex = 0
            return document.tracks.first
        }
    }
    
    // Create a workout based on visible segments
    private func createWorkoutFromSegments(_ segments: [GPXTrackSegment], originalTrack: GPXTrack) -> GPXWorkout {
        // Combine all locations from visible segments
        let allLocations = segments.flatMap { $0.locations }
        
        // If no visible segments, return the original workout
        if allLocations.isEmpty {
            return originalTrack.workout
        }
        
        // Sort locations by timestamp to get accurate start/end times
        let sortedLocations = allLocations.sorted { $0.timestamp < $1.timestamp }
        
        // Extract start and end dates from visible locations
        let startDate = sortedLocations.first?.timestamp ?? originalTrack.workout.startDate
        let endDate = sortedLocations.last?.timestamp ?? originalTrack.workout.endDate
        
        // Calculate total distance from visible segments
        var totalDistanceMeters: Double = 0
        if allLocations.count > 1 {
            for i in 0..<(allLocations.count - 1) {
                totalDistanceMeters += allLocations[i].distance(from: allLocations[i+1])
            }
        }
        
        // Create a new workout with data just from visible segments
        return GPXWorkout(
            activityType: originalTrack.activityType,
            startDate: startDate,
            endDate: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalDistance: totalDistanceMeters,
            metadata: originalTrack.workout.metadata
        )
    }

    var body: some View {
        ZStack {
            if !document.trackSegments.isEmpty {
                // Initialize data from document
                Color.clear
                    .onAppear {
                        updateFromDocument()
                        // Initialize overlay visibility from settings
                        isElevationOverlayVisible = settings.defaultShowElevationOverlay
                        isRouteInfoOverlayVisible = settings.defaultShowRouteInfoOverlay
                    }
                    .onChange(of: document.trackSegments.count) { oldValue, newValue in
                        updateFromDocument()
                    }
                
                // Main content with optional drawer
                HStack(spacing: 0) {
                    // Main map content
                    ZStack {
                        // Map view as the base layer
                        MapView(
                            trackSegments: visibleTrackSegments,
                            waypoints: waypointsVisible ? document.waypoints : [],
                            centerCoordinate: selectedWaypointCoordinate,
                            zoomLevel: 0.005, // Closer zoom when centering on a waypoint
                            spanAll: triggerSpanView, // Trigger to span view to all visible content
                            hoveredPointIndex: chartHoverPointIndex // Pass the currently hovered point index
                        )
                        .environmentObject(settings)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: triggerSpanView) { oldValue, newValue in
                            if newValue {
                                // Reset the trigger after it's been used
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    triggerSpanView = false
                                }
                            }
                        }
                        // Reset chart hover when user selects a waypoint
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WaypointSelected"))) { _ in
                            chartHoverPointIndex = nil
                            chartZoomRange = nil
                        }
                        
                        // Overlay with route information
                        if let track = selectedTrack {
                            // Create a workout based only on visible segments
                            let visibleWorkout = createWorkoutFromSegments(visibleTrackSegments, originalTrack: track)
                            
                            VStack {
                                // Route info at the top
                                if isRouteInfoOverlayVisible {
                                    RouteInfoOverlay(trackSegments: visibleTrackSegments, workout: visibleWorkout)
                                        .environmentObject(settings)
                                        .transition(.move(edge: .top))
                                        .animation(.easeInOut, value: isRouteInfoOverlayVisible)
                                }

                                Spacer()

                                // Elevation overlay at the bottom
                                if isElevationOverlayVisible && !visibleTrackSegments.isEmpty {
                                    ElevationOverlay(
                                        trackSegments: visibleTrackSegments,
                                        selectedPointIndex: $chartHoverPointIndex,
                                        zoomRange: $chartZoomRange
                                    )
                                    .environmentObject(settings)
                                    .transition(.move(edge: .bottom))
                                    .animation(.easeInOut, value: isElevationOverlayVisible)
                                }
                            }
                        }
                    }
                    #if os(iOS) || os(visionOS)
                    .toolbar(.visible, for: .navigationBar)
                    #endif
                    .toolbar {
                        // Map style menu
                        ToolbarItem(placement: .automatic) {
                            Menu {
                                ForEach(MapStyle.allCases) { style in
                                    Button {
                                        settings.mapStyle = style
                                    } label: {
                                        Label(style.rawValue, systemImage: style.iconName)
                                    }
                                }
                            } label: {
                                Label("Map Style", systemImage: "map")
                            }
                        }
                        
                        // Elevation overlay toggle
                        ToolbarItem(placement: .automatic) {
                            Button(action: {
                                isElevationOverlayVisible.toggle()
                            }) {
                                Label("Elevation", systemImage: "mountain.2")
                            }
                        }

                        // Route info overlay toggle
                        ToolbarItem(placement: .automatic) {
                            Button(action: {
                                isRouteInfoOverlayVisible.toggle()
                            }) {
                                Label("Route Info", systemImage: "info.circle")
                            }
                        }
                        
                        // Settings button
                        ToolbarItem(placement: .automatic) {
                            Button(action: {
                                isSettingsPresented = true
                            }) {
                                Label("Settings", systemImage: "gear")
                            }
                        }
                        
                        // Span to fit button
                        ToolbarItem(placement: .automatic) {
                            Button(action: {
                                // Clear any selected waypoint first
                                selectedWaypointCoordinate = nil
                                // Trigger the span view
                                triggerSpanView = true
                            }) {
                                Label("Fit to View", systemImage: "arrow.up.left.and.arrow.down.right")
                            }
                        }
                        
                        // Location button removed - now using MapKit's built-in user location tracking
                        
                        // Tracks drawer toggle
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
                                        Button("Done") {
                                            isSettingsPresented = false
                                        }
                                    }
                                }
                        }
                    }
                    
                    // Tracks drawer on the right (only shown when open)
                    if isTracksDrawerOpen {
                        TracksDrawer(
                            isOpen: $isTracksDrawerOpen,
                            document: $document,
                            visibleSegments: $visibleSegments,
                            selectedTrackIndex: $selectedTrackIndex,
                            segments: $segments,
                            waypointsVisible: $waypointsVisible,
                            selectedWaypointIndex: $selectedWaypointIndex,
                            onWaypointSelected: { coordinate in
                                // Update the state to center on this waypoint
                                selectedWaypointCoordinate = coordinate
                                // Post notification that a waypoint was selected
                                NotificationCenter.default.post(name: Notification.Name("WaypointSelected"), object: nil)
                            }
                        )
                        .environmentObject(settings)
                        .transition(.move(edge: .trailing))
                    }
                }
            } else {
                VStack {
                    Text("No valid GPX data found")
                        .font(.title)
                        .padding()
                    
                    Text("Open a GPX file to view the track on the map")
                        .foregroundColor(.secondary)
                }
            }
        }
        #if os(iOS)
        .navigationTitle(documentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updateDocumentTitle()
            updateFromDocument()
        }
        // Check for changes to the GPX file
        .onChange(of: document.gpxFile?.filename) { oldValue, newValue in
            updateDocumentTitle()
        }
        #elseif os(macOS)
        .onAppear {
            updateDocumentTitle()
            updateFromDocument()
        }
        // Check for changes to the GPX file
        .onChange(of: document.gpxFile?.filename) { oldValue, newValue in
            updateDocumentTitle()
        }
        #endif
    }
}

#Preview {
    ContentView(document: .constant(GPXExploreDocument()))
}
