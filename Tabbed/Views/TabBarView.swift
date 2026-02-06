import SwiftUI

struct TabBarView: View {
    @ObservedObject var group: TabGroup
    var onSwitchTab: (Int) -> Void
    var onReleaseTab: (Int) -> Void
    var onAddWindow: () -> Void
    var onMoveTab: (CGWindowID, CGWindowID) -> Void

    @State private var hoveredWindowID: CGWindowID? = nil

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(group.windows.enumerated()), id: \.element.id) { index, window in
                tabItem(for: window, at: index)
                    .onDrag {
                        NSItemProvider(object: String(window.id) as NSString)
                    }
                    .onDrop(of: [.text], delegate: TabDropDelegate(
                        targetWindowID: window.id,
                        onMoveTab: onMoveTab
                    ))
            }
            addButton
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func tabItem(for window: WindowInfo, at index: Int) -> some View {
        let isActive = index == group.activeIndex
        let isHovered = hoveredWindowID == window.id

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

struct TabDropDelegate: DropDelegate {
    let targetWindowID: CGWindowID
    let onMoveTab: (CGWindowID, CGWindowID) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        item.loadObject(ofClass: NSString.self) { string, _ in
            guard let string = string as? String,
                  let sourceID = CGWindowID(string) else { return }
            DispatchQueue.main.async {
                if sourceID != targetWindowID {
                    onMoveTab(sourceID, targetWindowID)
                }
            }
        }
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
