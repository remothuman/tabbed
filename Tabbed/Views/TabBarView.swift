import SwiftUI

struct TabBarView: View {
    @ObservedObject var group: TabGroup
    var onSwitchTab: (Int) -> Void
    var onReleaseTab: (Int) -> Void
    var onAddWindow: () -> Void

    @State private var hoveredWindowID: CGWindowID? = nil
    @State private var draggingID: CGWindowID? = nil
    @State private var dragOffset: CGFloat = 0
    /// Accumulated offset correction after each live swap so the tab stays under the cursor.
    @State private var dragAdjustment: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let tabCount = group.windows.count
            // Approximate tab step (width including inter-tab spacing) for swap detection.
            // The add button is fixed-width; the rest is split equally among tabs.
            let tabStep: CGFloat = tabCount > 0
                ? (geo.size.width - 8 - 28) / CGFloat(tabCount)
                : 0

            HStack(spacing: 1) {
                ForEach(Array(group.windows.enumerated()), id: \.element.id) { index, window in
                    let isDragging = draggingID == window.id

                    tabItem(for: window, at: index)
                        .offset(x: isDragging ? dragOffset : 0)
                        .zIndex(isDragging ? 1 : 0)
                        .scaleEffect(isDragging ? 1.03 : 1.0, anchor: .center)
                        .shadow(
                            color: isDragging ? .black.opacity(0.3) : .clear,
                            radius: isDragging ? 6 : 0,
                            y: isDragging ? 1 : 0
                        )
                        .gesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    handleDragChanged(
                                        windowID: window.id,
                                        translation: value.translation.width,
                                        tabStep: tabStep
                                    )
                                }
                                .onEnded { _ in
                                    handleDragEnded()
                                }
                        )
                }
                addButton
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drag Handling

    private func handleDragChanged(windowID: CGWindowID, translation: CGFloat, tabStep: CGFloat) {
        if draggingID == nil {
            draggingID = windowID
            dragAdjustment = 0
        }

        let effectiveOffset = translation + dragAdjustment
        dragOffset = effectiveOffset

        guard let currentIndex = group.windows.firstIndex(where: { $0.id == windowID }) else { return }

        // Swap right: dragged tab center has passed the midpoint of the next tab
        if effectiveOffset > tabStep / 2, currentIndex < group.windows.count - 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                group.moveTab(from: currentIndex, to: currentIndex + 2)
            }
            dragAdjustment -= tabStep
            dragOffset = translation + dragAdjustment
        }
        // Swap left: dragged tab center has passed the midpoint of the previous tab
        else if effectiveOffset < -tabStep / 2, currentIndex > 0 {
            withAnimation(.easeInOut(duration: 0.2)) {
                group.moveTab(from: currentIndex, to: currentIndex - 1)
            }
            dragAdjustment += tabStep
            dragOffset = translation + dragAdjustment
        }
    }

    private func handleDragEnded() {
        withAnimation(.easeOut(duration: 0.15)) {
            dragOffset = 0
            draggingID = nil
        }
        dragAdjustment = 0
    }

    // MARK: - Tab Item

    @ViewBuilder
    private func tabItem(for window: WindowInfo, at index: Int) -> some View {
        let isActive = index == group.activeIndex
        let isHovered = hoveredWindowID == window.id && draggingID == nil

        HStack(spacing: 6) {
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(window.title.isEmpty ? window.appName : window.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 12))
                .foregroundStyle(isActive ? .primary : .secondary)

            Spacer(minLength: 0)

            if isHovered {
                Button {
                    onReleaseTab(index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.primary.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSwitchTab(index)
        }
        .onHover { hovering in
            hoveredWindowID = hovering ? window.id : nil
        }
    }

    private var addButton: some View {
        Button {
            onAddWindow()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}
