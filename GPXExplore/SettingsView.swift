//
//  SettingsView.swift
//  GPXExplore
//
//  Created by Gavi Narra on 5/4/25.
//


import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    
    // Computed property to display the current density setting
    private var densityLabel: String {
        let value = settings.chartDataDensity
        if value <= 0.0 {
            return "Lowest"
        } else if value <= 0.3 {
            return "Low"
        } else if value <= 0.6 {
            return "Medium"
        } else if value <= 0.9 {
            return "High"
        } else {
            return "Maximum"
        }
    }
    
    var body: some View {
        #if os(macOS)
        // Use ScrollView + VStack for macOS to prevent section duplication in Form
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Units section
                GroupBox(label: Text("Units").font(.headline)) {
                    Toggle("Use Metric System (km)", isOn: $settings.useMetricSystem)
                        .padding(.top, 8)
                }
                
                // Map section
                GroupBox(label: Text("Map").font(.headline)) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("Map Style")
                                .padding(.top, 8)
                            Picker("Map Style", selection: $settings.mapStyle) {
                                ForEach(MapStyle.allCases) { style in
                                    Text(style.rawValue).tag(style)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Show My Location", isOn: $settings.userLocationEnabled)
                            
                            Text("Shows your current location on the map when enabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Elevation section
                GroupBox(label: Text("Elevation Visualization").font(.headline)) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Visualization mode
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Visualization Mode")
                                .padding(.top, 8)
                            Picker("Visualization Mode", selection: $settings.elevationVisualizationMode) {
                                ForEach(ElevationVisualizationMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            
                            Text(settings.elevationVisualizationMode.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                        
                        Divider()
                        
                        // Chart visibility
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Show Elevation Chart by Default", isOn: $settings.defaultShowElevationOverlay)
                                .padding(.vertical, 4)

                            Text("Controls whether the elevation chart overlay appears by default when opening GPX files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Toggle("Show Route Info by Default", isOn: $settings.defaultShowRouteInfoOverlay)
                                .padding(.vertical, 4)

                            Text("Controls whether the route information overlay appears by default when opening GPX files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Divider()
                        
                        // Track width
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Track Line Width: \(Int(settings.trackLineWidth))")
                            
                            Slider(
                                value: $settings.trackLineWidth,
                                in: 2...10,
                                step: 1
                            ) {
                                Text("Track Line Width")
                            } minimumValueLabel: {
                                Text("2")
                            } maximumValueLabel: {
                                Text("10")
                            }
                            
                            Text("Adjust the thickness of track lines on the map")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Divider()
                        
                        // Chart data density
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chart Data Density: \(densityLabel)")
                                .padding(.bottom, 4)
                            
                            Slider(
                                value: $settings.chartDataDensity,
                                in: 0...1,
                                step: 0.1
                            ) {
                                Text("Chart Data Density")
                            } minimumValueLabel: {
                                Text("Low")
                            } maximumValueLabel: {
                                Text("High")
                            }
                            
                            Text("Controls the number of data points shown in the elevation chart. Higher values show more detail but may impact performance with large tracks.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 600)
        .navigationTitle("Settings")
        #else
        // iOS version remains the same with Form
        Form {
            Section(header: Text("Units")) {
                Toggle("Use Metric System (km)", isOn: $settings.useMetricSystem)
            }
            
            Section(header: Text("Map")) {
                Picker("Map Style", selection: $settings.mapStyle) {
                    ForEach(MapStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Toggle("Show My Location", isOn: $settings.userLocationEnabled)
                
                Text("Shows your current location on the map when enabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Elevation Visualization")) {
                Picker("Visualization Mode", selection: $settings.elevationVisualizationMode) {
                    ForEach(ElevationVisualizationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Text(settings.elevationVisualizationMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                
                Divider()
                    .padding(.vertical, 8)
                
                Toggle("Show Elevation Chart by Default", isOn: $settings.defaultShowElevationOverlay)
                    .padding(.vertical, 4)

                Text("Controls whether the elevation chart overlay appears by default when opening GPX files")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)

                Toggle("Show Route Info by Default", isOn: $settings.defaultShowRouteInfoOverlay)
                    .padding(.vertical, 4)

                Text("Controls whether the route information overlay appears by default when opening GPX files")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                
                Divider()
                    .padding(.vertical, 8)
                
                Text("Track Line Width: \(Int(settings.trackLineWidth))")
                
                Slider(
                    value: $settings.trackLineWidth,
                    in: 2...10,
                    step: 1
                ) {
                    Text("Track Line Width")
                } minimumValueLabel: {
                    Text("2")
                } maximumValueLabel: {
                    Text("10")
                }
                
                Text("Adjust the thickness of track lines on the map")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                
                Divider()
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading) {
                    Text("Chart Data Density: \(densityLabel)")
                        .padding(.bottom, 4)
                    
                    Slider(
                        value: $settings.chartDataDensity,
                        in: 0...1,
                        step: 0.1
                    ) {
                        Text("Chart Data Density")
                    } minimumValueLabel: {
                        Text("Low")
                    } maximumValueLabel: {
                        Text("High")
                    }
                    
                    Text("Controls the number of data points shown in the elevation chart. Higher values show more detail but may impact performance with large tracks.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Settings")
        #endif
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsModel())
}
