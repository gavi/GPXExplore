import Foundation
import CoreGraphics

// Prints the CGWindowID of the frontmost on-screen document window owned by the named app,
// for `screencapture -l`. Used by shots.sh.
let name = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "GPX Explore"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    guard (w[kCGWindowOwnerName as String] as? String) == name,
          (w[kCGWindowLayer as String] as? Int) == 0,
          let id = w[kCGWindowNumber as String] as? Int else { continue }
    print(id)
    break
}
