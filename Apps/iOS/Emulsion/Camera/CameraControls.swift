import EmulsionKit
import EmulsionUI
import SwiftUI

/// Lenses, the shutter, the library and the recipe. A row under the viewfinder in portrait; a
/// vertical rail beside it when wide, with the format bar at its top and the library and recipe
/// at its foot.
struct CameraControls: View {
    let model: CameraModel
    let axis: Axis
    @Binding var showsLibrary: Bool
    let transition: Namespace.ID
    let isShowingRecipes: Bool
    /// Nil where the recipe strip is always visible.
    let toggleRecipes: (() -> Void)?

    @Environment(PhotoStore.self) private var store

    var body: some View {
        controls
            // Like the system Camera, controls stop growing at the largest accessibility
            // sizes so the viewfinder keeps its room; long-press shows each label large.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder private var controls: some View {
        if axis == .vertical {
            // At accessibility text sizes the rail can outgrow a short screen; it scrolls
            // then instead of clipping.
            ViewThatFits(in: .vertical) {
                rail
                ScrollView { rail }.scrollIndicators(.hidden)
            }
        } else {
            VStack(spacing: FilmLabLayout.space) {
                lenses
                // Equal flexible sides keep the shutter centred.
                HStack {
                    library.frame(maxWidth: .infinity, alignment: .leading)
                    shutter
                    recipe.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var rail: some View {
        VStack(spacing: FilmLabLayout.gap) {
            // Everything but the shutter lies across the rail, so it fits a phone's landscape
            // height (about 350 pt inside the safe area and margins on iPhone 17 Pro).
            CaptureFormatBar(capabilities: model.capabilities)
            Spacer(minLength: 0)
            lenses
            shutter
            Spacer(minLength: 0)
            HStack(spacing: FilmLabLayout.compact) {
                library
                recipe
            }
        }
    }

    @ViewBuilder private var lenses: some View {
        if let capabilities = model.capabilities, capabilities.lenses.count > 1 {
            LensPicker(capabilities: capabilities) { lens in Task { await model.select(lens) } }
                .disabled(model.isCapturing)
        }
    }

    private var shutter: some View {
        ShutterButton(isEnabled: model.status == .running && !model.isCapturing, captureCount: model.captureCount) {
            Task { await model.capture() }
        }
    }

    private var recipe: some View {
        RecipeButton(recipe: model.recipe, isShowingRecipes: isShowingRecipes, toggle: toggleRecipes)
    }

    private var library: some View {
        LibraryButton(photo: model.lastCapture ?? store.photos.first, transition: transition) { showsLibrary = true }
    }
}
