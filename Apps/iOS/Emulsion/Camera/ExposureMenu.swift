import EmulsionKit
import EmulsionUI
import SwiftUI

struct ExposureMenu: View {
    let exposure: CameraExposure
    let change: (CameraExposure.Change) -> Void

    var body: some View {
        Menu {
            if exposure.supportsManual || exposure.isManual {
                Button {
                    change(.automatic)
                } label: {
                    choice("Auto Exposure", selected: !exposure.isManual)
                }
            }
            if exposure.supportsManual {
                shutterMenu
                isoMenu
            }
            if exposure.apertureStops.isEmpty {
                Text("Aperture (apertureTitle(exposure.aperture))")
            } else {
                apertureMenu
            }
        } label: {
            Label("Exposure", systemImage: "camera.aperture")
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: FilmLabLayout.minimumControlHeight, height: FilmLabLayout.minimumControlHeight)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .foregroundStyle(exposure.isManual ? Color.yellow : Color.primary)
        .menuOrder(.fixed)
        .accessibilityLabel("Exposure")
        .accessibilityValue(exposure.isManual ? Text("Manual") : Text("Auto"))
        .accessibilityShowsLargeContentViewer()
    }

    private var shutterMenu: some View {
        Menu {
            ForEach(exposure.shutterStops, id: \.self) { seconds in
                Button {
                    change(.shutter(seconds: seconds))
                } label: {
                    let title = shutterTitle(seconds)
                    choice(title, selected: exposure.isManual && title == shutterTitle(exposure.shutterSeconds))
                }
            }
        } label: {
            Text(exposure.isManual ? "Shutter Speed · (shutterTitle(exposure.shutterSeconds))" : "Shutter Speed")
        }
    }

    private var isoMenu: some View {
        Menu {
            ForEach(exposure.isoStops, id: \.self) { iso in
                Button {
                    change(.iso(iso))
                } label: {
                    let title = isoTitle(iso)
                    choice(title, selected: exposure.isManual && title == isoTitle(exposure.iso))
                }
            }
        } label: {
            Text(exposure.isManual ? "ISO · (isoTitle(exposure.iso))" : "ISO")
        }
    }

    private var apertureMenu: some View {
        Menu {
            ForEach(exposure.apertureStops, id: \.self) { aperture in
                Button {
                    change(.aperture(aperture))
                } label: {
                    let title = apertureTitle(aperture)
                    choice(title, selected: exposure.isManual && title == apertureTitle(exposure.aperture))
                }
            }
        } label: {
            Text("Aperture · (apertureTitle(exposure.aperture))")
        }
    }

    private func choice(_ title: String, selected: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            if selected { Image(systemName: "checkmark") }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func shutterTitle(_ seconds: Double) -> String {
        guard seconds > 0, seconds.isFinite else { return "—" }
        if seconds < 1 {
            return "1/((1 / seconds).formatted(.number.grouping(.never).precision(.fractionLength(0))))"
        }
        return "(seconds.formatted(.number.precision(.fractionLength(0...1)))) s"
    }

    private func isoTitle(_ iso: Float) -> String {
        iso.formatted(.number.grouping(.never).precision(.fractionLength(0)))
    }

    private func apertureTitle(_ aperture: Float) -> String {
        "ƒ/(aperture.formatted(.number.precision(.fractionLength(1...2))))"
    }
}
