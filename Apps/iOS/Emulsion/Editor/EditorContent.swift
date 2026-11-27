import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

struct EditorContent: View {
    @Bindable var session: EditSession

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var group = AdjustmentGroup.light
    @State private var selection: [AdjustmentGroup: String] = [:]
    @State private var isComparing = false
    @State private var isHolding = false
    @State private var showsLookTray = false
    @State private var candidate: Recipe?
    @State private var isConfirmingLook = false
    /// Nil until the user taps Adjust; until then the canvas decides.
    @State private var adjustmentsPreference: Bool?

    private var showsOriginal: Bool { isComparing || isHolding }
    private let verticalPanelWidth: CGFloat = 128
    private let outerPanelWidth: CGFloat = 96
    private let minimumVerticalPanelHeight: CGFloat = 250

    var body: some View {
        GeometryReader { geometry in
            let isExpanded = geometry.isExpandedCanvas(horizontalSizeClass: horizontalSizeClass, verticalSizeClass: verticalSizeClass)
            let showsAdjustments = !showsLookTray && (adjustmentsPreference ?? isExpanded)
            workspace(geometry, isExpanded: isExpanded, showsAdjustments: showsAdjustments)
                .toolbar {
                    EditorToolbar(
                        session: session, isComparing: $isComparing, showsAdjustments: showsAdjustments,
                        showsLookTray: showsLookTray, toggleLookTray: toggleLookTray,
                        toggleAdjustments: {
                            closeLookTray()
                            adjustmentsPreference = !showsAdjustments
                        })
                }
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .tint(.white)
        .navigationTitle(showsOriginal ? Text("Original") : Text(""))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isComparing) { _, isComparing in
            if isComparing { closeLookTray() }
        }
        .alert("Replace current adjustments?", isPresented: $isConfirmingLook, presenting: candidate) { recipe in
            Button("Apply \(recipe.name)") { applyLook(recipe) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Applying a look replaces the adjustments on this photo.")
        }
        .task { await session.editorAppeared() }
    }

    @ViewBuilder
    private func workspace(_ geometry: GeometryProxy, isExpanded: Bool, showsAdjustments: Bool) -> some View {
        if #available(iOS 27.1, *) {
            EditorAdjustmentAxis(hasDivision: !geometry.reservedRegions(kind: .division, options: .includeInactive).isEmpty) { vertical in
                adaptiveWorkspace(
                    isExpanded: isExpanded, showsAdjustments: showsAdjustments,
                    usesVerticalPanel: vertical && geometry.size.height >= minimumVerticalPanelHeight)
            }
        } else {
            compactLayout(height: geometry.size.height, showsAdjustments: showsAdjustments)
        }
    }

    @available(iOS 27.1, *)
    @ViewBuilder private func adaptiveWorkspace(isExpanded: Bool, showsAdjustments: Bool, usesVerticalPanel: Bool) -> some View {
        if isExpanded {
            ArrangementWorkspace(showsInspector: showsAdjustments, narrowInspectorWidth: usesVerticalPanel ? verticalPanelWidth : nil) {
                photoWithLookTray(isVertical: usesVerticalPanel)
                    .padding(FilmLabLayout.inset)
            } inspector: {
                if usesVerticalPanel {
                    verticalPanel
                } else {
                    AdjustmentInspector(
                        adjustments: $session.adjustments, group: $group, selection: $selection,
                        whiteBalanceAsShot: session.asShotWhiteBalance
                    )
                    .disabled(showsOriginal)
                }
            }
        } else if usesVerticalPanel {
            UnobscuredContent {
                HStack(spacing: showsAdjustments ? FilmLabLayout.compact : 0) {
                    photoWithLookTray(isVertical: true)
                    verticalPanel
                        .frame(width: showsAdjustments ? outerPanelWidth : 0)
                        .clipped()
                        .opacity(showsAdjustments ? 1 : 0)
                        .allowsHitTesting(showsAdjustments)
                        .accessibilityHidden(!showsAdjustments)
                }
                .padding(.horizontal, FilmLabLayout.compact)
            }
        } else {
            // Always wrapped, so an occlusion appearing doesn't rebuild the photo.
            UnobscuredContent {
                GeometryReader { unobscured in
                    compactLayout(height: unobscured.size.height, showsAdjustments: showsAdjustments)
                }
            }
        }
    }

    private var verticalPanel: some View {
        VerticalAdjustmentPanel(
            adjustments: $session.adjustments, group: $group, selection: $selection,
            whiteBalanceAsShot: session.asShotWhiteBalance
        )
        .frame(maxWidth: verticalPanelWidth)
        .disabled(showsOriginal)
    }

    private func photoWithLookTray(isVertical: Bool) -> some View {
        ComparablePhoto(
            url: session.url, adjustments: candidate?.applying(to: session.adjustments) ?? session.adjustments,
            isComparing: isComparing, previewLookName: candidate?.name, isHolding: $isHolding
        )
        .overlay(alignment: isVertical ? .trailing : .bottom) {
            if showsLookTray {
                QuickLooksTray(session: session, isVertical: isVertical, candidate: $candidate, close: closeLookTray, apply: confirmLook)
                    .padding(FilmLabLayout.compact)
            }
        }
    }

    private func compactLayout(height: CGFloat, showsAdjustments: Bool) -> some View {
        CompactEditorLayout(
            height: height, showsAdjustments: showsAdjustments, isEditable: !showsOriginal,
            whiteBalanceAsShot: session.asShotWhiteBalance, adjustments: $session.adjustments, group: $group, selection: $selection
        ) {
            photoWithLookTray(isVertical: verticalSizeClass == .compact)
        }
    }

    private func toggleLookTray() {
        if showsLookTray { closeLookTray() } else { showsLookTray = true }
    }

    private func closeLookTray() {
        candidate = nil
        showsLookTray = false
    }

    private func confirmLook() {
        guard let candidate else { return }
        if session.isEdited && !candidate.matches(session.adjustments) {
            isConfirmingLook = true
        } else {
            applyLook(candidate)
        }
    }

    private func applyLook(_ recipe: Recipe) {
        session.apply(recipe)
        closeLookTray()
    }
}
