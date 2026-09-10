import AppKit
import SwiftUI
import DayLineCore

/// A native split view keeps divider dragging smooth while SwiftUI owns the
/// sidebar and timeline content.  The saved ratio is only changed when a user
/// finishes dragging a divider; AppKit resize/layout updates never write it.
struct AdaptiveMainSplitView<Sidebar: View, Detail: View>: NSViewRepresentable {
    let sidebarRatio: Double
    let sidebar: Sidebar
    let detail: Detail
    let onRatioChange: (Double) -> Void

    init(
        sidebarRatio: Double,
        onRatioChange: @escaping (Double) -> Void,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebarRatio = sidebarRatio
        self.onRatioChange = onRatioChange
        self.sidebar = sidebar()
        self.detail = detail()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onRatioChange: onRatioChange) }

    func makeNSView(context: Context) -> TrackingSplitView {
        let splitView = TrackingSplitView()
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator
        splitView.translatesAutoresizingMaskIntoConstraints = false

        let sidebarHost = NSHostingView(rootView: sidebar)
        let detailHost = NSHostingView(rootView: detail)
        sidebarHost.translatesAutoresizingMaskIntoConstraints = true
        detailHost.translatesAutoresizingMaskIntoConstraints = true
        sidebarHost.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detailHost.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sidebarHost.setContentHuggingPriority(.defaultLow, for: .vertical)
        detailHost.setContentHuggingPriority(.defaultLow, for: .vertical)
        splitView.addSubview(sidebarHost)
        splitView.addSubview(detailHost)

        splitView.onDividerTrackingEnded = { [weak coordinator = context.coordinator, weak splitView] in
            guard let coordinator, let splitView else { return }
            coordinator.finishDividerDrag(in: splitView)
        }
        context.coordinator.sidebarHost = sidebarHost
        context.coordinator.detailHost = detailHost
        context.coordinator.applyLayout(to: splitView, ratio: sidebarRatio)
        return splitView
    }

    func updateNSView(_ splitView: TrackingSplitView, context: Context) {
        context.coordinator.onRatioChange = onRatioChange
        context.coordinator.sidebarHost?.rootView = sidebar
        context.coordinator.detailHost?.rootView = detail
        guard !splitView.isTrackingDivider else { return }
        context.coordinator.applyLayout(to: splitView, ratio: sidebarRatio)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        weak var sidebarHost: NSHostingView<Sidebar>?
        weak var detailHost: NSHostingView<Detail>?
        var onRatioChange: (Double) -> Void
        private var isStacked: Bool?
        private var savedRatio = MainSplitLayout.defaultRatio
        private var isApplyingLayout = false

        init(onRatioChange: @escaping (Double) -> Void) {
            self.onRatioChange = onRatioChange
        }

        func applyLayout(to splitView: TrackingSplitView, ratio: Double) {
            savedRatio = MainSplitLayout.clampedRatio(CGFloat(ratio))
            let stacked = MainSplitLayout.shouldStack(width: splitView.bounds.width, height: splitView.bounds.height)
            if isStacked != stacked {
                splitView.isVertical = !stacked
                isStacked = stacked
            }
            guard splitView.subviews.count == 2 else { return }
            let minimums = MainSplitLayout.minimums(stacked: stacked)
            let length = stacked ? splitView.bounds.height : splitView.bounds.width
            let position = MainSplitLayout.dividerPosition(
                ratio: savedRatio,
                containerLength: length,
                minimumFirst: minimums.first,
                minimumSecond: minimums.second,
                dividerThickness: splitView.dividerThickness
            )
            isApplyingLayout = true
            splitView.setPosition(position, ofDividerAt: 0)
            isApplyingLayout = false
        }

        func finishDividerDrag(in splitView: TrackingSplitView) {
            let stacked = MainSplitLayout.shouldStack(width: splitView.bounds.width, height: splitView.bounds.height)
            let minimums = MainSplitLayout.minimums(stacked: stacked)
            let length = stacked ? splitView.bounds.height : splitView.bounds.width
            // A constrained tiny window must not replace the user's preferred
            // ratio with the temporary pixel-limited divider position.
            guard MainSplitLayout.canFitMinimums(
                containerLength: length,
                minimumFirst: minimums.first,
                minimumSecond: minimums.second,
                dividerThickness: splitView.dividerThickness
            ) else { return }
            let position = stacked ? splitView.subviews[0].frame.height : splitView.subviews[0].frame.width
            let ratio = MainSplitLayout.ratio(
                forDividerPosition: position,
                containerLength: length,
                dividerThickness: splitView.dividerThickness
            )
            savedRatio = ratio
            onRatioChange(Double(ratio))
        }

        func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            let stacked = !splitView.isVertical
            let minimums = MainSplitLayout.minimums(stacked: stacked)
            let length = stacked ? splitView.bounds.height : splitView.bounds.width
            return MainSplitLayout.dividerPosition(
                ratio: MainSplitLayout.ratio(
                    forDividerPosition: proposedPosition,
                    containerLength: length,
                    dividerThickness: splitView.dividerThickness
                ),
                containerLength: length,
                minimumFirst: minimums.first,
                minimumSecond: minimums.second,
                dividerThickness: splitView.dividerThickness
            )
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard !isApplyingLayout,
                  let splitView = notification.object as? TrackingSplitView,
                  !splitView.isTrackingDivider else { return }
            // Window resizing is display-only. It lays out with the last
            // saved value and deliberately never calls onRatioChange.
            applyLayout(to: splitView, ratio: Double(savedRatio))
        }
    }
}

final class TrackingSplitView: NSSplitView {
    var onDividerTrackingEnded: (() -> Void)?
    private(set) var isTrackingDivider = false

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let dividerRect: NSRect
        if isVertical, let first = subviews.first {
            dividerRect = NSRect(x: first.frame.maxX - 4, y: 0, width: dividerThickness + 8, height: bounds.height)
        } else if let first = subviews.first {
            dividerRect = NSRect(x: 0, y: first.frame.maxY - 4, width: bounds.width, height: dividerThickness + 8)
        } else {
            dividerRect = .zero
        }
        let tracksDivider = dividerRect.contains(point)
        if tracksDivider { isTrackingDivider = true }
        super.mouseDown(with: event)
        if tracksDivider {
            isTrackingDivider = false
            onDividerTrackingEnded?()
        }
    }
}
