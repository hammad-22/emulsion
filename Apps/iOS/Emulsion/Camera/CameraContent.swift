import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

struct CameraContent: View {
    @Bindable var model: CameraModel
    @Binding var showsLibrary: Bool
    let transition: Namespace.ID

    @Environment(RecipeStore.self) private var savedLooks
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsRecipes = false

    private static let recipesAnimation = Animation.snappy(duration: 0.3)
    private static let reducedMotionRecipesAnimation = Animation.easeInOut(duration: 0.2)

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: FilmLabLayout.inset) {
                    stage
                    controls(axis: .vertical)
                }
            } else {
                VStack(spacing: FilmLabLayout.gap) {
                    CaptureFormatBar(model: model)
                    stage
                    controls(axis: .horizontal)
                }
            }
        }
        .padding(FilmLabLayout.inset)
        .alert(Text(model.error?.localizedDescription ?? ""), isPresented: Binding(isPresenting: $model.error)) {}
    }

    private var stage: some View {
        VStack(spacing: FilmLabLayout.gap) {
            viewfinder(showingRecipes: showsRecipes && !alwaysShowsRecipes)
            if alwaysShowsRecipes { recipeStrip }
        }
    }

    @ViewBuilder private func viewfinder(showingRecipes: Bool) -> some View {
        switch model.status {
        case .unauthorized:
            CameraUnavailableView(reason: .denied)
        case .restricted:
            CameraUnavailableView(reason: .restricted)
        case .unavailable:
            CameraUnavailableView(reason: .unavailable { Task { await model.start() } })
        case .idle, .starting, .running, .interrupted:
            ViewfinderView(model: model) {
                viewfinderControls(showingRecipes: showingRecipes)
            }
        }
    }

    private func viewfinderControls(showingRecipes: Bool) -> some View {
        VStack(spacing: FilmLabLayout.compact) {
            if showingRecipes {
                recipeStrip
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            if !isWide, let capabilities = model.capabilities, capabilities.lenses.count > 1 {
                LensPicker(capabilities: capabilities) { option in
                    Task { await model.select(option.lens, zoomFactor: option.zoomFactor) }
                }
                .disabled(!model.acceptsInput)
                .dynamicTypeSize(...FilmLabLayout.largestCameraTextSize)
            }
        }
        .padding(.bottom, FilmLabLayout.gap)
    }

    private var recipeStrip: some View {
        RecipeStrip(recipes: CuratedLooks.recipes + savedLooks.recipes, selection: model.recipe) { model.recipe = $0 }
    }

    private func controls(axis: Axis) -> some View {
        let toggle: (() -> Void)? = alwaysShowsRecipes ? nil : { toggleRecipes() }
        return CameraControls(
            model: model, axis: axis, showsLibrary: $showsLibrary, transition: transition,
            isShowingRecipes: showsRecipes || alwaysShowsRecipes, toggleRecipes: toggle)
    }

    private func toggleRecipes() {
        withAnimation(reduceMotion ? Self.reducedMotionRecipesAnimation : Self.recipesAnimation) { showsRecipes.toggle() }
    }

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }
    private var alwaysShowsRecipes: Bool { horizontalSizeClass == .regular && verticalSizeClass == .regular }
}
