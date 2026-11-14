import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

/// The recipe strip lies over the viewfinder on demand, so the viewfinder never changes size;
/// on iPhone Duo unfolded it sits beneath it all the time.
struct CameraContent: View {
    @Bindable var model: CameraModel
    @Binding var showsLibrary: Bool
    let transition: Namespace.ID

    @Environment(RecipeStore.self) private var savedLooks
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsRecipes = false

    private let recipesAnimation = Animation.snappy(duration: 0.3)
    private let reducedMotionRecipesAnimation = Animation.easeInOut(duration: 0.2)

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: FilmLabLayout.inset) {
                    stage
                    controls(axis: .vertical)
                }
            } else {
                VStack(spacing: FilmLabLayout.gap) {
                    CaptureFormatBar(capabilities: model.capabilities)
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
                if showingRecipes {
                    recipeStrip
                        .padding(.bottom, FilmLabLayout.gap)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
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
        withAnimation(reduceMotion ? reducedMotionRecipesAnimation : recipesAnimation) { showsRecipes.toggle() }
    }

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }
    /// Room for the viewfinder plus the strip: iPhone Duo unfolded.
    private var alwaysShowsRecipes: Bool { horizontalSizeClass == .regular && verticalSizeClass == .regular }
}
