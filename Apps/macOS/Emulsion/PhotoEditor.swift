import EmulsionKit
import EmulsionUI
import SwiftUI

struct PhotoEditor: View {
    @State private var session: EditSession
    @State private var showsOriginal = false
    @State private var group = AdjustmentGroup.light
    @Environment(\.scenePhase) private var scenePhase

    // Fits the same labels and controls as the iPhone panel, with room to resize.
    private let minimumPanelWidth: CGFloat = 340
    private let maximumPanelWidth: CGFloat = 400
    // Keep a useful photo area when the window or split divider is resized.
    private let minimumPhotoSize: CGFloat = 320

    init(photo: PhotoRecord, store: PhotoStore) {
        _session = State(initialValue: EditSession(photo: photo, store: store))
    }

    var body: some View {
        @Bindable var session = session
        HSplitView {
            RenderedPhoto(url: session.url, adjustments: session.adjustments, showsOriginal: showsOriginal)
                .accessibilityLabel(showsOriginal ? "Original photo" : "Edited photo")
                .accessibilityAddTraits(.isImage)
                .padding()
                .frame(minWidth: minimumPhotoSize, minHeight: minimumPhotoSize)
            ScrollView {
                AdjustmentPanel(adjustments: $session.adjustments, group: $group)
                    .padding()
            }
            .frame(minWidth: minimumPanelWidth, idealWidth: minimumPanelWidth, maxWidth: maximumPanelWidth)
        }
        .toolbar {
            Toggle("Compare", systemImage: "square.split.2x1", isOn: $showsOriginal)
            Button("Reset Edits", systemImage: "arrow.counterclockwise") { session.reset() }
        }
        .onDisappear { session.close() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.close() }
        }
        // Quitting doesn't change the scene phase, so a pending edit is written here.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.close()
        }
    }
}
