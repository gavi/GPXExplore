import Foundation
import MapKit
import SwiftUI
import CoreLocation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Renders the visible tracks onto a MapKit snapshot, coloured exactly as on screen, with the
// chart underneath, and writes a PNG the share sheet or a save panel can take.
enum MapImageExporter {
    struct Options {
        var mapStyle: MapStyle
        var visualization: ElevationVisualizationMode
        var lineWidth: CGFloat
        var size = CGSize(width: 1600, height: 1000)
        var chartHeight: CGFloat = 320
        var title: String
        var subtitle: String
    }

    enum ExportError: Error { case snapshotFailed, encodeFailed }

    static func export(segments: [GPXTrackSegment], stats: TrackStatistics, chartImage: CGImage?, options: Options) async throws -> URL {
        let locations = segments.flatMap { $0.locations }
        guard !locations.isEmpty else { throw ExportError.snapshotFailed }

        let snapOptions = MKMapSnapshotter.Options()
        snapOptions.region = region(for: locations)
        snapOptions.size = options.size
        #if os(iOS)
        snapOptions.scale = 2
        #endif
        snapOptions.preferredConfiguration = options.mapStyle.mapConfiguration
        snapOptions.showsBuildings = false
        // Always a light map: the picture goes to other people, not to this screen's appearance
        #if os(iOS)
        snapOptions.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        #elseif os(macOS)
        snapOptions.appearance = NSAppearance(named: .aqua)
        #endif

        let snapshot = try await MKMapSnapshotter(options: snapOptions).start()

        let mapImage = snapshot.image
        let scale: CGFloat = 2
        let width = Int(options.size.width * scale)
        let mapHeight = Int(options.size.height * scale)
        let chartHeightPx = chartImage == nil ? 0 : Int(options.chartHeight * scale)
        let headerHeight = Int(90 * scale)
        let totalHeight = mapHeight + chartHeightPx + headerHeight

        guard let ctx = CGContext(data: nil, width: width, height: totalHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ExportError.encodeFailed
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: totalHeight))

        // Map at the top (CoreGraphics origin is bottom-left)
        let mapRect = CGRect(x: 0, y: chartHeightPx + headerHeight, width: width, height: mapHeight)
        if let cg = cgImage(mapImage) { ctx.draw(cg, in: mapRect) }

        // Tracks, in the current colouring
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(chartHeightPx + headerHeight))
        // Snapshot points: top-left origin on iOS (flip into CG space), bottom-left already on macOS
        func cg(_ p: CGPoint) -> CGPoint {
            #if os(iOS)
            return CGPoint(x: p.x * scale, y: (options.size.height - p.y) * scale)
            #else
            return CGPoint(x: p.x * scale, y: p.y * scale)
            #endif
        }
        ctx.setLineWidth(options.lineWidth * scale)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let minE = stats.minElevation ?? 0, maxE = stats.maxElevation ?? 0
        for segment in segments where segment.locations.count > 1 {
            let pts = segment.locations.map { snapshot.point(for: $0.coordinate) }
            let grades = segment.hasElevation ? TrackGrades.grades(for: segment.locations) : []
            for i in 0..<(pts.count - 1) {
                let rgb: TrackColors.RGB
                if !segment.hasElevation {
                    rgb = TrackColors.noElevation
                } else if options.visualization == .effort {
                    rgb = TrackColors.rgbForGrade(grades[i])
                } else {
                    let t = maxE > minE ? (segment.locations[i].altitude - minE) / (maxE - minE) : 0.5
                    rgb = TrackColors.rgbForElevationFraction(t)
                }
                ctx.setStrokeColor(TrackColors.cgColor(rgb))
                ctx.beginPath()
                ctx.move(to: cg(pts[i]))
                ctx.addLine(to: cg(pts[i + 1]))
                ctx.strokePath()
            }
        }
        // Start and end dots
        if let first = locations.first, let last = locations.last {
            for (loc, color) in [(first, CGColor(red: 0.2, green: 0.75, blue: 0.3, alpha: 1)), (last, CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1))] {
                let c = cg(snapshot.point(for: loc.coordinate))
                let r = 7 * scale
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: c.x - r - 2 * scale, y: c.y - r - 2 * scale, width: 2 * r + 4 * scale, height: 2 * r + 4 * scale))
                ctx.setFillColor(color); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }
        }
        ctx.restoreGState()

        // Chart under the map
        if let chartImage = chartImage {
            ctx.draw(chartImage, in: CGRect(x: 0, y: headerHeight, width: width, height: chartHeightPx))
        }

        // Header strip at the bottom: title and the numbers
        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: headerHeight))
        draw(text: options.title, at: CGPoint(x: 24 * scale, y: 50 * scale), size: 26 * scale, bold: true, in: ctx, width: width)
        draw(text: options.subtitle, at: CGPoint(x: 24 * scale, y: 18 * scale), size: 16 * scale, bold: false, in: ctx, width: width)
        draw(text: "GPX Explore", at: CGPoint(x: CGFloat(width) - 24 * scale, y: 18 * scale), size: 14 * scale, bold: false, in: ctx, width: width, alignRight: true)
        ctx.restoreGState()

        guard let image = ctx.makeImage() else { throw ExportError.encodeFailed }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(safeFilename(options.title) + ".png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw ExportError.encodeFailed }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.encodeFailed }
        return url
    }

    private static func region(for locations: [CLLocation]) -> MKCoordinateRegion {
        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        for l in locations {
            minLat = min(minLat, l.coordinate.latitude); maxLat = max(maxLat, l.coordinate.latitude)
            minLon = min(minLon, l.coordinate.longitude); maxLon = max(maxLon, l.coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.3, 0.005), longitudeDelta: max((maxLon - minLon) * 1.3, 0.005))
        return MKCoordinateRegion(center: center, span: span)
    }

    private static func draw(text: String, at point: CGPoint, size: CGFloat, bold: Bool, in ctx: CGContext, width: Int, alignRight: Bool = false) {
        let font = CTFontCreateWithName((bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, [])
        var origin = point
        if alignRight { origin.x -= bounds.width }
        ctx.textPosition = origin
        CTLineDraw(line, ctx)
    }

    private static func safeFilename(_ s: String) -> String {
        let cleaned = s.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ")).inverted).joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "GPX Explore" : trimmed
    }

    #if os(iOS)
    private static func cgImage(_ image: UIImage) -> CGImage? { image.cgImage }
    #elseif os(macOS)
    private static func cgImage(_ image: NSImage) -> CGImage? { image.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    #endif
}


extension MapImageExporter {
    // SwiftUI chart → bitmap, on the main actor; call before export(…)
    @MainActor
    static func renderChart<V: View>(_ chart: V, width: CGFloat, height: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: chart.frame(width: width, height: height).background(Color.white))
        renderer.scale = 2
        return renderer.cgImage
    }
}
