import Foundation

/// The spectral responsivities Π_c(λ) of one density definition (Status M, a printing density), red, green and blue,
/// sampled on a wavelength grid. Integral density through them is ST 2065-2:2020 Eq. 1 (FILM-THEORY §2):
///
///     D_c = −log10( Σ_λ Π_c(λ)·10^(−D(λ)) / Σ_λ Π_c(λ) )
///
/// The sums run over the grid; the constant Δλ cancels.
struct SpectralResponsivities: Sendable, Equatable {
    enum Channel: String, CaseIterable, Codable, Sendable { case red, green, blue }

    /// The grid every responsivity and dye spectrum is evaluated on, in nm: spans every table read (Status M from
    /// 410 nm, APD from 360 nm to 730 nm, the negatives' dye charts to 800 nm) at the dye charts' 5 nm step.
    static let grid = Array(stride(from: 360.0, through: 800, by: 5))

    let name: String
    let wavelengths: [Double]
    /// Red, green, blue; each one weight per wavelength.
    let channels: [[Double]]

    /// Integral densities (red, green, blue) of a spectral density D(λ) sampled on `wavelengths`.
    func densities(of spectralDensity: [Double]) -> [Double] {
        let transmittance = spectralDensity.map { pow(10, -$0) }
        return channels.map { weights in -log10(weights.dot(transmittance) / weights.reduce(0, +)) }
    }
}
