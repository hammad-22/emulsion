import Foundation

/// Π_c(λ) of one density definition; integral density per ST 2065-2:2020 Eq. 1.
struct SpectralResponsivities: Sendable, Equatable {
    enum Channel: String, CaseIterable, Codable, Sendable { case red, green, blue }

    /// 360–800 nm at the dye charts' 5 nm: spans every table read.
    static let grid = Array(stride(from: 360.0, through: 800, by: 5))

    let name: String
    let wavelengths: [Double]
    let channels: [[Double]]

    func densities(of spectralDensity: [Double]) -> [Double] {
        let transmittance = spectralDensity.map { pow(10, -$0) }
        return channels.map { weights in -log10(weights.dot(transmittance) / weights.reduce(0, +)) }
    }
}
