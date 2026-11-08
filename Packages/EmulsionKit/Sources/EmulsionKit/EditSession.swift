import EmulsionCore
import Foundation
import Observation

/// One photo open in the editor. Slider moves update `adjustments` at once (the preview
/// follows them); the library index is written once they rest, and on `close()`, so
/// leaving the editor mid-drag never loses the last change.
@MainActor @Observable
public final class EditSession {
    public let photo: PhotoRecord
    public var adjustments: Adjustments {
        didSet { scheduleSave() }
    }

    private let store: PhotoStore
    @ObservationIgnored private(set) var pendingSave: Task<Void, Never>?
    /// Long enough to skip the writes during a drag, short enough to survive a crash.
    static let saveDelay: Duration = .milliseconds(300)

    public init(photo: PhotoRecord, store: PhotoStore) {
        self.photo = photo
        self.store = store
        adjustments = photo.adjustments
    }

    public var url: URL { store.url(for: photo) }

    /// Back to the default look; the photo keeps its grain pattern.
    public func reset() {
        adjustments = .defaults(for: photo.id)
    }

    /// Writes any pending change now. Call when the editor goes away.
    public func close() {
        pendingSave?.cancel()
        pendingSave = nil
        store.update(photo.id, adjustments: adjustments)
    }

    /// Develops at full resolution with the current edit and adds the result to Photos.
    public func saveToPhotos(format: Renderer.ExportFormat) async throws {
        let data = try await store.renderService.export(url, adjustments, format: format)
        try await PhotoLibrarySaver.save(data)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self else { return }
            store.update(photo.id, adjustments: adjustments)
        }
    }
}
