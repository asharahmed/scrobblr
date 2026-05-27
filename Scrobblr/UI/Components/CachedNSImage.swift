import SwiftUI
import AppKit

/// Renders an `NSImage` from `Data`, but caches the decoded NSImage so
/// SwiftUI doesn't re-decode the bytes on every body re-evaluation.
///
/// The previous pattern was:
///
/// ```swift
/// if let data, let img = NSImage(data: data) { Image(nsImage: img).resizable() }
/// ```
///
/// That constructs (and lazily decodes) a fresh NSImage every time the
/// parent view's body runs. During smooth-progress playback the menu bar
/// re-evaluates 4 times per second, which means a fresh decode of a
/// 600x600 JPEG four times a second per visible artwork view. CachedNSImage
/// stores the decoded NSImage in `@State` and only re-decodes when the
/// underlying `Data` identity changes via `.task(id: data)`.
struct CachedNSImage: View {
    let data: Data?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .task(id: data) {
            // Decoding can be slow for very large images; do it off-Main.
            if let data {
                let decoded = await Task.detached(priority: .userInitiated) {
                    NSImage(data: data)
                }.value
                await MainActor.run { withAnimation { image = decoded } }
            } else {
                image = nil
            }
        }
    }
}
