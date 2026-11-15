import EmulsionUI
import SwiftUI

struct CoolingNote: View {
    var body: some View {
        Label("Preview slowed while iPhone cools", systemImage: "thermometer.medium")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, FilmLabLayout.gap)
            .padding(.vertical, FilmLabLayout.compact)
            .glassEffect(.regular, in: .capsule)
            .allowsHitTesting(false)
    }
}
