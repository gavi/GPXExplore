import SwiftUI

// Shows the exported picture and offers to share it (and, on the Mac, to save it)
struct ExportSheet: View {
    let imageURL: URL
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            if let image = loadImage() {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 640, maxHeight: 520)
                    .cornerRadius(8)
                    .shadow(radius: 4)
            }
            HStack(spacing: 12) {
                ShareLink(item: imageURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                #if os(macOS)
                Button {
                    save()
                } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
                #endif
                Button("Done") { dismiss(); onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 4)
        }
        .padding()
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        #endif
    }

    private func loadImage() -> Image? {
        #if os(iOS)
        guard let ui = UIImage(contentsOfFile: imageURL.path) else { return nil }
        return Image(uiImage: ui)
        #elseif os(macOS)
        guard let ns = NSImage(contentsOf: imageURL) else { return nil }
        return Image(nsImage: ns)
        #endif
    }

    #if os(macOS)
    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = imageURL.lastPathComponent
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let target = panel.url {
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: imageURL, to: target)
        }
    }
    #endif
}
