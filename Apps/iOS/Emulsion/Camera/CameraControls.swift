import EmulsionKit
import EmulsionUI
import SwiftUI

struct CameraControls: View {
    let model: CameraModel
    let axis: Axis
    @Binding var showsLibrary: Bool
    let transition: Namespace.ID
    let isShowingRecipes: Bool
    let toggleRecipes: (() -> Void)?

    @Environment(PhotoStore.self) private var store

    var body: some View {
        controls
            .dynamicTypeSize(...FilmLabLayout.largestCameraTextSize)
    }

    @ViewBuilder private var controls: some View {
        if axis == .vertical {
            ViewThatFits(in: .vertical) {
                rail
                ScrollView { rail }.scrollIndicators(.hidden)
            }
        } else {
            HStack {
                library.frame(maxWidth: .infinity, alignment: .leading)
                shutter
                recipe.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var rail: some View {
        VStack(spacing: FilmLabLayout.gap) {
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
            LensPicker(capabilities: capabilities) { option in
                Task { await model.select(option.lens, zoomFactor: option.zoomFactor) }
            }
            .disabled(!model.acceptsInput)
        }
    }

    private var shutter: some View {
        ShutterButton(isEnabled: model.acceptsInput, captureCount: model.captureCount) {
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
