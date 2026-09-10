import SwiftUI
import CoreLocation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct TracksDrawer: View {
    @Binding var isOpen: Bool
    @Binding var document: GPXExploreDocument
    @Binding var visibleSegments: [Bool]
    @Binding var selectedTrackIndex: Int
    @Binding var segments: [GPXTrackSegment]
    @Binding var waypointsVisible: Bool
    @Binding var selectedWaypointIndex: Int
    @EnvironmentObject var settings: SettingsModel

    // Beside the map (iPad, Mac) the drawer is a 280-point panel; in the phone's sheet it fills the width
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
    #else
    private var compact: Bool { false }
    #endif
    
    // Optional closure to call when a waypoint is selected
    var onWaypointSelected: ((CLLocationCoordinate2D) -> Void)?
    
    // Track expansion states
    @State private var expandedTracks: [Bool] = []
    @State private var waypointsExpanded: Bool = true
    
    // Helper function to calculate segment length
    private func calculateSegmentLength(_ locations: [CLLocation]) -> Double {
        guard locations.count > 1 else { return 0 }
        
        var totalDistance: Double = 0
        for i in 0..<(locations.count - 1) {
            totalDistance += locations[i].distance(from: locations[i+1])
        }
        
        return totalDistance
    }
    
    // Helper function to toggle segment visibility
    private func toggleAllSegments() {
        let allVisible = visibleSegments.allSatisfy { $0 }
        // If all are visible, hide all; otherwise show all
        for i in 0..<visibleSegments.count {
            visibleSegments[i] = !allVisible
        }
    }
    
    // Helper function to toggle all segments in a track
    private func toggleTrackSegments(trackIndex: Int) {
        // Get indices of all segments belonging to this track
        let trackSegmentIndices = segments.indices.filter { segments[$0].trackIndex == trackIndex }
        
        // Check if all segments in this track are visible
        let allVisible = trackSegmentIndices.allSatisfy { visibleSegments[$0] }
        
        // Toggle all segments in this track
        for index in trackSegmentIndices {
            visibleSegments[index] = !allVisible
        }
    }
    
    // Initialize expansion states when tracks change
    private func initializeExpandedStates() {
        if expandedTracks.count != document.tracks.count {
            expandedTracks = Array(repeating: true, count: document.tracks.count)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Tracks & Waypoints")
                    .font(.headline)
                    .padding(.vertical, 8)
                
                Spacer()
            }
            .padding(.horizontal)
            .onChange(of: document.tracks.count) { oldValue, newValue in
                initializeExpandedStates()
            }
            .onAppear {
                initializeExpandedStates()
            }
            
            Divider()
            
            // Tree View of tracks, segments, and waypoints
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Tracks and segments
                    ForEach(0..<document.tracks.count, id: \.self) { trackIndex in
                        let track = document.tracks[trackIndex]
                        let isExpanded = expandedTracks.indices.contains(trackIndex) ? expandedTracks[trackIndex] : true
                        
                        // Track row with disclosure triangle
                        TrackRow(
                            track: track,
                            trackIndex: trackIndex,
                            isSelected: selectedTrackIndex == trackIndex,
                            isExpanded: isExpanded,
                            onSelect: {
                                selectedTrackIndex = trackIndex
                            },
                            onToggle: {
                                if expandedTracks.indices.contains(trackIndex) {
                                    expandedTracks[trackIndex].toggle()
                                }
                            },
                            onToggleVisibility: {
                                toggleTrackSegments(trackIndex: trackIndex)
                            },
                            visibleSegments: $visibleSegments,
                            segments: $segments
                        )
                        
                        // Segment rows (only show if track is expanded)
                        if isExpanded {
                            let trackSegmentIndices = segments.indices.filter { segments[$0].trackIndex == trackIndex }
                            ForEach(Array(trackSegmentIndices.enumerated()), id: \.element) { (localIndex, segmentIndex) in
                                let segment = segments[segmentIndex]
                                let pointCount = segment.locations.count
                                
                                if pointCount > 0 {
                                    SegmentRow(
                                        segment: segment,
                                        segmentIndex: segmentIndex,
                                        localSegmentIndex: localIndex, // Pass the local segment index
                                        isVisible: visibleSegments.indices.contains(segmentIndex) ? visibleSegments[segmentIndex] : true,
                                        onToggleVisibility: {
                                            if visibleSegments.indices.contains(segmentIndex) {
                                                visibleSegments[segmentIndex].toggle()
                                            }
                                        },
                                        distanceFormatter: settings.formatDistance
                                    )
                                }
                            }
                        }
                    }
                    
                    // Only show waypoints section if there are waypoints
                    if !document.waypoints.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Waypoints section header with disclosure triangle
                        WaypointsHeaderRow(
                            waypointCount: document.waypoints.count,
                            isExpanded: waypointsExpanded,
                            isVisible: waypointsVisible,
                            onToggle: {
                                waypointsExpanded.toggle()
                            },
                            onToggleVisibility: {
                                waypointsVisible.toggle()
                            }
                        )
                        
                        // Waypoint rows (only show if expanded)
                        if waypointsExpanded {
                            ForEach(0..<document.waypoints.count, id: \.self) { waypointIndex in
                                let waypoint = document.waypoints[waypointIndex]
                                WaypointRow(
                                    waypoint: waypoint,
                                    waypointIndex: waypointIndex,
                                    isSelected: selectedWaypointIndex == waypointIndex,
                                    onSelect: {
                                        // Update selected waypoint index
                                        selectedWaypointIndex = waypointIndex
                                        
                                        // Trigger the map to center on this waypoint
                                        if let action = onWaypointSelected {
                                            action(waypoint.coordinate)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: compact ? nil : 280)
        .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
        #if os(iOS)
        .background(Color(UIColor.systemBackground))
        .overlay(
            Rectangle()
                .frame(width: compact ? 0 : 1, height: nil, alignment: .leading)
                .foregroundColor(Color(UIColor.separator))
                .opacity(0.5),
            alignment: .leading
        )
        #else
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(width: 1, height: nil, alignment: .leading)
                .foregroundColor(Color.gray)
                .opacity(0.5),
            alignment: .leading
        )
        #endif
    }
}

// Track row component
struct TrackRow: View {
    let track: GPXTrack
    let trackIndex: Int
    let isSelected: Bool
    let isExpanded: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onToggleVisibility: () -> Void
    @Binding var visibleSegments: [Bool]
    @Binding var segments: [GPXTrackSegment]
    
    // Check if all segments in this track are hidden
    private var areAllSegmentsHidden: Bool {
        let trackSegmentIndices = segments.indices.filter { segments[$0].trackIndex == trackIndex }
        return trackSegmentIndices.allSatisfy { !visibleSegments[$0] }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Disclosure triangle
            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .frame(width: 16, height: 16)
                    #if os(iOS)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    #else
                    .foregroundColor(Color.secondary)
                    #endif
            }
            .buttonStyle(BorderlessButtonStyle())
            
            // Visibility toggle for all segments in track
            Button(action: onToggleVisibility) {
                Image(systemName: areAllSegmentsHidden ? "eye.slash" : "eye")
                    .frame(width: 20, height: 20)
                    #if os(iOS)
                    .foregroundColor(areAllSegmentsHidden ? Color(UIColor.systemGray) : Color(UIColor.systemBlue))
                    #else
                    .foregroundColor(areAllSegmentsHidden ? Color.gray : Color.accentColor)
                    #endif
            }
            .buttonStyle(BorderlessButtonStyle())
            
            // Track name
            Text(track.name.isEmpty ? "Track \(trackIndex + 1)" : track.name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .padding(.vertical, 6)
            
            Spacer()
            
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    #if os(iOS)
                    .foregroundColor(Color(UIColor.systemBlue))
                    #else
                    .foregroundColor(Color.accentColor)
                    #endif
            }
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        #if os(iOS)
        .background(isSelected ? Color(UIColor.systemBlue).opacity(0.1) : Color.clear)
        #else
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        #endif
    }
}

// Segment row component
struct SegmentRow: View {
    let segment: GPXTrackSegment
    let segmentIndex: Int
    let localSegmentIndex: Int // Track-specific segment index (starting from 0 for each track)
    let isVisible: Bool
    let onToggleVisibility: () -> Void
    let distanceFormatter: (Double) -> String
    
    // Helper to calculate segment length
    private var segmentLength: Double {
        guard segment.locations.count > 1 else { return 0 }
        
        var totalDistance: Double = 0
        for i in 0..<(segment.locations.count - 1) {
            totalDistance += segment.locations[i].distance(from: segment.locations[i+1])
        }
        
        return totalDistance
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Indentation
            Spacer()
                .frame(width: 16)
            
            // Visibility toggle
            Button(action: onToggleVisibility) {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .frame(width: 20, height: 20)
                    #if os(iOS)
                    .foregroundColor(isVisible ? Color(UIColor.systemBlue) : Color(UIColor.systemGray))
                    #else
                    .foregroundColor(isVisible ? Color.accentColor : Color.gray)
                    #endif
            }
            .buttonStyle(BorderlessButtonStyle())
            
            // Segment info
            VStack(alignment: .leading, spacing: 2) {
                Text("Segment \(localSegmentIndex + 1)")
                    .font(.system(size: 13))
                
                HStack(spacing: 8) {
                    Text("\(segment.locations.count) points")
                        .font(.system(size: 11))
                        #if os(iOS)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        #else
                        .foregroundColor(Color.secondary)
                        #endif
                    
                    if segment.locations.count > 1 {
                        Text(distanceFormatter(segmentLength))
                            .font(.system(size: 11))
                            #if os(iOS)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            #else
                            .foregroundColor(Color.secondary)
                            #endif
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .padding(.leading, 20) // Indentation for hierarchy
        #if os(iOS)
        .background(isVisible ? Color(UIColor.systemBlue).opacity(0.05) : Color.clear)
        #else
        .background(isVisible ? Color.accentColor.opacity(0.05) : Color.clear)
        #endif
    }
}

// Waypoints header row component
struct WaypointsHeaderRow: View {
    let waypointCount: Int
    let isExpanded: Bool
    let isVisible: Bool
    let onToggle: () -> Void
    let onToggleVisibility: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Disclosure triangle
            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .frame(width: 16, height: 16)
                    #if os(iOS)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    #else
                    .foregroundColor(Color.secondary)
                    #endif
            }
            .buttonStyle(BorderlessButtonStyle())
            
            // Visibility toggle
            Button(action: onToggleVisibility) {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .frame(width: 20, height: 20)
                    #if os(iOS)
                    .foregroundColor(isVisible ? Color(UIColor.systemBlue) : Color(UIColor.systemGray))
                    #else
                    .foregroundColor(isVisible ? Color.accentColor : Color.gray)
                    #endif
            }
            .buttonStyle(BorderlessButtonStyle())
            
            // Header text
            Text("Waypoints (\(waypointCount))")
                .font(.system(size: 14, weight: .bold))
                .padding(.vertical, 6)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}

// Waypoint row component
struct WaypointRow: View {
    let waypoint: GPXWaypoint
    let waypointIndex: Int
    let isSelected: Bool
    var onSelect: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            // Indentation
            Spacer()
                .frame(width: 16)
            
            // Waypoint icon
            Image(systemName: getIconForWaypoint(waypoint))
                .frame(width: 20, height: 20)
                #if os(iOS)
                .foregroundColor(isSelected ? Color(UIColor.systemBlue) : Color(UIColor.systemPurple))
                #else
                .foregroundColor(isSelected ? Color.accentColor : Color.purple)
                #endif
            
            // Waypoint info
            VStack(alignment: .leading, spacing: 2) {
                Text(waypoint.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .fontWeight(isSelected ? .bold : .regular)
                
                if let description = waypoint.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        #if os(iOS)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        #else
                        .foregroundColor(Color.secondary)
                        #endif
                }
                
                if let elevation = waypoint.elevation {
                    Text("Elevation: \(Int(elevation))m")
                        .font(.system(size: 11))
                        #if os(iOS)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        #else
                        .foregroundColor(Color.secondary)
                        #endif
                }
            }
            
            Spacer()
            
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    #if os(iOS)
                    .foregroundColor(Color(UIColor.systemBlue))
                    #else
                    .foregroundColor(Color.accentColor)
                    #endif
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .padding(.leading, 20) // Indentation for hierarchy
        .contentShape(Rectangle()) // Make the entire row tappable
        .onTapGesture {
            if let action = onSelect {
                action()
            }
        }
        #if os(iOS)
        .background(isSelected ? Color(UIColor.systemBlue).opacity(0.1) : Color(UIColor.systemPurple).opacity(0.05))
        .cornerRadius(4)
        #else
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.purple.opacity(0.05))
        .cornerRadius(4)
        #endif
    }
    
    // Helper to determine icon based on waypoint symbol or name
    private func getIconForWaypoint(_ waypoint: GPXWaypoint) -> String {
        if let symbol = waypoint.symbol {
            // Match common GPX symbols to SF Symbols
            switch symbol.lowercased() {
            case "flag", "summit":
                return "flag"
            case "campground", "camp":
                return "tent"
            case "water", "drinking-water":
                return "drop"
            case "parking":
                return "car"
            case "info", "information":
                return "info.circle"
            case "danger", "caution":
                return "exclamationmark.triangle"
            case "restaurant", "food":
                return "fork.knife"
            default:
                break
            }
        }
        
        // Fallback to matching by name
        let name = waypoint.name.lowercased()
        if name.contains("parking") || name.contains("car") {
            return "car"
        } else if name.contains("water") {
            return "drop"
        } else if name.contains("camp") {
            return "tent"
        } else if name.contains("summit") || name.contains("peak") {
            return "mountain.2"
        } else if name.contains("food") || name.contains("restaurant") {
            return "fork.knife"
        } else if name.contains("info") {
            return "info.circle"
        } else if name.contains("danger") || name.contains("caution") {
            return "exclamationmark.triangle"
        }
        
        // Default icon
        return "mappin"
    }
}

// Extension to use in ContentView for toolbar button
extension TracksDrawer {
    static func toolbarButton(isOpen: Binding<Bool>) -> some View {
        Button(action: {
            withAnimation(.spring()) {
                isOpen.wrappedValue.toggle()
            }
        }) {
            Label("Tracks", systemImage: isOpen.wrappedValue ? "sidebar.right" : "sidebar.right")
        }
    }
}

#Preview {
    let mockSegments = [
        GPXTrackSegment(locations: [CLLocation(latitude: 0, longitude: 0)], trackIndex: 0),
        GPXTrackSegment(locations: [CLLocation(latitude: 1, longitude: 1)], trackIndex: 0),
        GPXTrackSegment(locations: [CLLocation(latitude: 2, longitude: 2)], trackIndex: 1)
    ]
    
    // Create a document with some sample XML data
    let mockDoc = GPXExploreDocument(text: "<gpx></gpx>")
    
    // Create a mock document with tracks for preview
    let doc = mockDoc
    
    // Since we can't directly modify the properties, we're just using the
    // document as is and providing the segments separately
    
    TracksDrawer(
        isOpen: .constant(true),
        document: .constant(doc),
        visibleSegments: .constant([true, false, true]),
        selectedTrackIndex: .constant(0),
        segments: .constant(mockSegments),
        waypointsVisible: .constant(true),
        selectedWaypointIndex: .constant(1), // Preview with second waypoint selected
        onWaypointSelected: { coordinate in
            print("Waypoint selected at \(coordinate.latitude), \(coordinate.longitude)")
        }
    )
    .environmentObject(SettingsModel())
}