import EmulsionCore
import EmulsionKit
import EmulsionUI
import SwiftUI

/// Portrait: the format bar, the viewfinder, then lenses and the shutter below it.
/// Wide (landscape, iPhone Duo unfolded): the viewfinder on the leading side and the same
/// controls in a trailing rail. The recipe strip appears over the viewfinder's bottom edge on
/// demand, so the viewfinder never changes size; on a regular-width, regular-height canvas
/// (iPhone Duo unfolded) it sits beneath the viewfinder all the time.
struct CameraContent: View {
    @Bindable var model: CameraModel
    @Binding var showsLibrary: Bool
    let transition: Namespace.ID

    @Environment(RecipeStore.self) private var savedLooks
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsRecipes = false

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
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3)) { showsRecipes.toggle() }
    }

    /// The same rule as the editor: a regular-width or compact-height canvas.
    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }
    /// Room for the viewfinder plus the strip: iPhone Duo unfolded.
    private var alwaysShowsRecipes: Bool { horizontalSizeClass == .regular && verticalSizeClass == .regular }
}
