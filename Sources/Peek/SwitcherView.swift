import SwiftUI
import AppKit

final class SwitcherState: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex = 0
    @Published var columns = 1
    var commitHandler: ((Int) -> Void)?
    var cancelHandler: (() -> Void)?
    var hoverHandler: ((Int) -> Void)?
}

struct SwitcherView: View {
    @ObservedObject var state: SwitcherState

    private let thumbnailSize = CGSize(width: 240, height: 150)

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(thumbnailSize.width + 24), spacing: 20),
                                 count: max(1, state.columns)),
                  spacing: 24) {
            ForEach(Array(state.windows.enumerated()), id: \.element.id) { index, window in
                cell(for: window, selected: index == state.selectedIndex)
                    .background(HoverTracker { state.hoverHandler?(index) })
                    .onTapGesture { state.commitHandler?(index) }
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func cell(for window: WindowInfo, selected: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                Text(window.title.isEmpty ? window.appName : window.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: thumbnailSize.width)

            Group {
                if let thumbnail = window.thumbnail {
                    Image(decorative: thumbnail, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                } else if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 72, height: 72)
                }
            }
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Color.primary.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .contentShape(Rectangle())
    }
}

/// SwiftUI's `onHover` does not fire reliably inside a non-activating panel.
/// This NSView tracks the mouse with `.activeAlways`, which always works.
private struct HoverTracker: NSViewRepresentable {
    let onHover: () -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.onHover = onHover
    }

    final class TrackerView: NSView {
        var onHover: (() -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onHover?() }
        override func mouseMoved(with event: NSEvent) { onHover?() }
    }
}
