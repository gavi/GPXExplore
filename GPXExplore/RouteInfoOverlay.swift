import SwiftUI
import CoreLocation

// The route card: what a person wants to know about the visible track at a glance,
// and the splits behind a disclosure. Every number comes from TrackStatistics.
struct RouteInfoOverlay: View {
    let stats: TrackStatistics
    let trackName: String
    var trackDescription: String? = nil
    @EnvironmentObject var settings: SettingsModel
    @State private var splitsExpanded = false
    @State private var expanded = false

    // On a phone the map is the point: the card starts as a one-line strip (name,
    // distance, time, pace) and opens to the full card on tap. Wide screens show it all.
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
    #else
    private var compact: Bool { false }
    #endif

    private var metric: Bool { settings.useMetricSystem }

    var body: some View {
        VStack {
            Group {
                if compact && !expanded {
                    strip
                } else {
                    card
                }
            }
            .padding(compact ? 10 : 16)
            #if os(iOS)
            .background(Color(UIColor.systemBackground).opacity(0.85))
            #elseif os(macOS)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
            #endif
            .cornerRadius(12)
            // The whole card, padding included, is the hit area: a miss used to fall through
            // to the map, where a second tap zooms it. Children keep their own gestures.
            .contentShape(Rectangle())
            .onTapGesture {
                if compact && !expanded { withAnimation(.easeInOut(duration: 0.2)) { expanded = true } }
            }
            .padding(.horizontal, compact ? 10 : 16)
            .padding(.top, compact ? 8 : 16)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
    }

    // MARK: Compact strip

    private var headline: String {
        var parts = [StatsFormat.distance(stats.distance, metric: metric)]
        if let moving = stats.movingTime { parts.append(StatsFormat.duration(moving)) }
        if let pace = stats.averagePace, let speed = stats.averageSpeed {
            parts.append(paceStyle ? StatsFormat.pace(pace, metric: metric) : StatsFormat.speed(speed, metric: metric))
        }
        return parts.joined(separator: "  ·  ")
    }

    private var strip: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(trackName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(headline).font(.caption.monospacedDigit()).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.down").font(.body.weight(.semibold)).foregroundColor(.secondary)
                .frame(width: 32, height: 32)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trackName), \(headline). Show details")
    }

    // MARK: Full card

    private var card: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Name, and the file's description when it has one (not on a phone: no room)
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trackName).font(.headline).lineLimit(1)
                        if !compact, let d = trackDescription, !d.isEmpty {
                            Text(d).font(.caption).foregroundColor(.secondary).lineLimit(2)
                        }
                    }
                    if compact {
                        Spacer(minLength: 4)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { expanded = false }
                        } label: {
                            Image(systemName: "chevron.up").font(.body.weight(.semibold)).foregroundColor(.secondary)
                                .frame(width: 44, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hide details")
                    }
                }

                // Headline: distance · moving time · pace or speed
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    stat(StatsFormat.distance(stats.distance, metric: metric), "Distance", .title3)
                    if let moving = stats.movingTime {
                        stat(StatsFormat.duration(moving), "Moving", .title3)
                    }
                    if let pace = stats.averagePace, let speed = stats.averageSpeed {
                        if paceStyle {
                            stat(StatsFormat.pace(pace, metric: metric), "Avg pace", .title3)
                        } else {
                            stat(StatsFormat.speed(speed, metric: metric), "Avg speed", .title3)
                        }
                    }
                    Spacer(minLength: 0)
                }

                // Second line: when, elapsed, max speed, points
                HStack(spacing: 12) {
                    if let start = stats.startDate {
                        Text("\(start, style: .date) \(start, style: .time)")
                    }
                    if let elapsed = stats.elapsedTime, let moving = stats.movingTime, elapsed - moving > 60 {
                        Text("Elapsed \(StatsFormat.duration(elapsed))")
                    }
                    if let maxSpeed = stats.maxSpeed {
                        Text("Max \(StatsFormat.speed(maxSpeed, metric: metric))")
                    }
                    if !compact {
                        Text("\(stats.pointCount) points · \(stats.segmentCount) segment\(stats.segmentCount == 1 ? "" : "s")")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

                // Elevation, only when the file has it
                if stats.hasElevation, let minE = stats.minElevation, let maxE = stats.maxElevation {
                    Divider()
                    HStack(spacing: 14) {
                        stat("+\(StatsFormat.elevation(stats.elevationGain ?? 0, metric: metric))", "Gain", .subheadline)
                        stat("−\(StatsFormat.elevation(stats.elevationLoss ?? 0, metric: metric))", "Loss", .subheadline)
                        stat(StatsFormat.elevation(minE, metric: metric), "Min", .subheadline)
                        stat(StatsFormat.elevation(maxE, metric: metric), "Max", .subheadline)
                        Spacer(minLength: 0)
                        legend
                    }
                }

                // Sensors, only what the file carries
                if stats.heartRate != nil || stats.power != nil || stats.cadence != nil || stats.temperature != nil {
                    Divider()
                    HStack(spacing: 14) {
                        if let hr = stats.heartRate {
                            stat("\(Int(hr.average.rounded())) / \(Int(hr.max.rounded())) bpm", "Heart rate avg / max", .subheadline, color: TrackColors.heartRate)
                        }
                        if let p = stats.power {
                            stat("\(Int(p.average.rounded())) / \(Int(p.max.rounded())) W", "Power avg / max", .subheadline, color: TrackColors.power)
                        }
                        if let c = stats.cadence {
                            stat("\(Int(c.average.rounded())) rpm", "Cadence", .subheadline, color: TrackColors.cadence)
                        }
                        if let t = stats.temperature {
                            stat("\(StatsFormat.temperature(t.min, metric: metric))–\(StatsFormat.temperature(t.max, metric: metric))", "Temperature", .subheadline, color: TrackColors.temperature)
                        }
                        Spacer(minLength: 0)
                    }
                }

                // Splits
                if stats.splits.count > 1 {
                    Divider()
                    DisclosureGroup(isExpanded: $splitsExpanded) {
                        splitsTable
                    } label: {
                        Text("Splits, per \(metric ? "km" : "mi")")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation { splitsExpanded.toggle() } }
                    }
                }
            }
    }

    // Runners read pace, everyone else reads speed
    private var paceStyle: Bool {
        guard let speed = stats.averageSpeed else { return false }
        return speed < 4.0   // under ~14 km/h: walking, hiking, running
    }

    private func stat(_ value: String, _ label: String, _ font: Font, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(font).fontWeight(.semibold).foregroundColor(color).lineLimit(1)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private var legend: some View {
        HStack(spacing: 6) {
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0, green: 0.3, blue: 1.0), Color(red: 0, green: 1.0, blue: 0.0), Color(red: 1.0, green: 0.2, blue: 0.0)]),
                startPoint: .bottom, endPoint: .top
            )
            .frame(width: 6, height: 34)
            .cornerRadius(3)
            VStack(alignment: .leading) {
                Text("High").font(.system(size: 8)).foregroundColor(.secondary)
                Spacer()
                Text("Low").font(.system(size: 8)).foregroundColor(.secondary)
            }
            .frame(height: 34)
        }
        .accessibilityHidden(true)
    }

    // Scrolls inside a fixed height: a bare frame(maxHeight:) let a long table draw over
    // the label and the chevron, which made the group impossible to collapse
    private var splitsTable: some View {
        ScrollView(.vertical) {
            splitsRows
        }
        .frame(maxHeight: 160)
        .padding(.top, 4)
    }

    private var splitsRows: some View {
        VStack(spacing: 2) {
            HStack {
                Text("#").frame(width: 28, alignment: .leading)
                Text("Time").frame(width: 64, alignment: .leading)
                Text(paceStyle ? "Pace" : "Speed").frame(width: 92, alignment: .leading)
                Text("Elev").frame(width: 60, alignment: .leading)
                Spacer()
            }
            .font(.caption2).foregroundColor(.secondary)
            ForEach(stats.splits) { split in
                HStack {
                    Text("\(split.index)").frame(width: 28, alignment: .leading)
                    Text(split.movingTime.map { StatsFormat.duration($0) } ?? "—").frame(width: 64, alignment: .leading)
                    Text(splitPaceText(split)).frame(width: 92, alignment: .leading)
                    Text(split.elevationChange.map { ($0 >= 0 ? "+" : "−") + StatsFormat.elevation(abs($0), metric: metric) } ?? "—").frame(width: 60, alignment: .leading)
                    Spacer()
                }
                .font(.caption.monospacedDigit())
            }
        }
    }

    private func splitPaceText(_ split: TrackStatistics.Split) -> String {
        guard let pace = split.pace, pace > 0 else { return "—" }
        return paceStyle ? StatsFormat.pace(pace, metric: metric) : StatsFormat.speed(1 / pace, metric: metric)
    }
}
