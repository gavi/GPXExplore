import Foundation
import SwiftUI
import CoreLocation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// The one place the track colours live. The map renderers, the image exporter and the chart
// legend all read from here so the exported picture matches the screen.
enum TrackColors {
    // Grade thresholds (Garmin-like): under 3 % easy, under 8 % moderate, under 15 % steep
    static let moderateGrade = 0.03
    static let steepGrade = 0.08
    static let verySteepGrade = 0.15

    struct RGB { let r: CGFloat, g: CGFloat, b: CGFloat }

    // Effort mode: uphill green → orange → red, downhill light blue → blue → purple
    static func rgbForGrade(_ grade: Double) -> RGB {
        let g = min(max(grade, -verySteepGrade), verySteepGrade)
        if g >= 0 {
            if g < moderateGrade { return RGB(r: 0.0, g: 0.8, b: 0.0) }
            if g < steepGrade { return RGB(r: 1.0, g: 0.6, b: 0.0) }
            return RGB(r: 1.0, g: 0.1, b: 0.0)
        } else {
            let a = -g
            if a < moderateGrade { return RGB(r: 0.0, g: 0.5, b: 1.0) }
            if a < steepGrade { return RGB(r: 0.0, g: 0.3, b: 0.9) }
            if a < verySteepGrade { return RGB(r: 0.3, g: 0.0, b: 0.8) }
            return RGB(r: 0.4, g: 0.2, b: 0.8)
        }
    }

    // Gradient mode: position of an elevation between the track's min and max, 0…1,
    // mapped deep blue → cyan → green → yellow → orange → red
    static func rgbForElevationFraction(_ t: Double) -> RGB {
        let stops: [(Double, RGB)] = [
            (0.0, RGB(r: 0.0, g: 0.2, b: 0.8)), (0.25, RGB(r: 0.0, g: 0.8, b: 0.9)), (0.5, RGB(r: 0.1, g: 0.8, b: 0.2)),
            (0.75, RGB(r: 1.0, g: 0.85, b: 0.0)), (0.9, RGB(r: 1.0, g: 0.5, b: 0.0)), (1.0, RGB(r: 0.9, g: 0.1, b: 0.1)),
        ]
        let x = min(max(t, 0), 1)
        for i in 1..<stops.count where x <= stops[i].0 {
            let (x0, c0) = stops[i - 1], (x1, c1) = stops[i]
            let f = x1 > x0 ? (x - x0) / (x1 - x0) : 0
            return RGB(r: c0.r + (c1.r - c0.r) * f, g: c0.g + (c1.g - c0.g) * f, b: c0.b + (c1.b - c0.b) * f)
        }
        return stops.last!.1
    }

    // Flat colour for tracks without elevation data
    static let noElevation = RGB(r: 0.2, g: 0.45, b: 0.95)

    static func cgColor(_ c: RGB) -> CGColor { CGColor(red: c.r, green: c.g, blue: c.b, alpha: 1) }
    static func color(_ c: RGB) -> Color { Color(red: c.r, green: c.g, blue: c.b) }
    #if os(iOS)
    static func platformColor(_ c: RGB) -> UIColor { UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1) }
    #elseif os(macOS)
    static func platformColor(_ c: RGB) -> NSColor { NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1) }
    #endif

    // Metric series colours for the chart
    static let heartRate = Color(red: 0.9, green: 0.2, blue: 0.25)
    static let power = Color(red: 0.55, green: 0.3, blue: 0.9)
    static let cadence = Color(red: 0.95, green: 0.6, blue: 0.1)
    static let speed = Color(red: 0.1, green: 0.5, blue: 0.95)
    static let temperature = Color(red: 0.1, green: 0.65, blue: 0.65)
}

// Grade per point from a location list, smoothed the way the map renderer does it,
// so the exporter and Quick Look colour exactly like the on-screen track.
enum TrackGrades {
    static func grades(for locations: [CLLocation]) -> [Double] {
        let n = locations.count
        guard n > 1 else { return Array(repeating: 0, count: n) }
        var ele = locations.map { $0.altitude }
        // moving average, adaptive window
        if n > 3 {
            let w = min(5, n / 20 + 2)
            let src = ele
            for i in 0..<n {
                let lo = max(0, i - w), hi = min(n - 1, i + w)
                ele[i] = src[lo...hi].reduce(0, +) / Double(hi - lo + 1)
            }
        }
        var grades = Array(repeating: 0.0, count: n)
        let window = min(5, n / 10 + 1)
        for i in 0..<(n - 1) {
            let lo = max(0, i - window), hi = min(n - 1, i + window)
            guard hi > lo else { continue }
            let dist = locations[lo].distance(from: locations[hi])
            if dist > 5 { grades[i] = min(max((ele[hi] - ele[lo]) / dist, -0.45), 0.45) }
        }
        if n > 1 { grades[n - 1] = grades[n - 2] }
        return grades
    }
}
