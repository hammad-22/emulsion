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
    /// The white balance a RAW photo was shot at, where its Temperature and Tint rulers rest;
    /// nil until `readAsShotWhiteBalance()` has read it, and for photos that aren't RAW.
    public private(set) var asShotWhiteBalance: CameraWhiteBalance?

    private let store: PhotoStore
    @ObservationIgnored private(set) var pendingSave: Task<Void, Never>?
    /// Long enough to skip the writes during a drag, short enough to survive a crash.
    static let saveDelay: Duration = .milliseconds(300)

    public init(photo: PhotoRecord, store: PhotoStore) {
        self.photo = photo
        self.store = store
        adjustments = photo.adjustments
        store.renderService.open(store.url(for: photo))
    }

    /// Reads a RAW photo's as-shot white balance, which gives the editor its White Balance
    /// rulers. Call from the editor's `.task`; the file is read off the main actor.
    public func readAsShotWhiteBalance() async {
        guard photo.isRAW, asShotWhiteBalance == nil else { return }
        asShotWhiteBalance = await store.renderService.asShotWhiteBalance(url)
    }

    public var url: URL { store.url(for: photo) }

    /// True while there is something for `reset()` to undo.
    public var isEdited: Bool { adjustments != .defaults(for: photo.id) }

    /// Back to the default look, with the RAW white balance as shot; the photo keeps its grain pattern.
    public func reset() {
        adjustments = .defaults(for: photo.id)
    }

    /// Replaces adjustment values only. Originals and this photo's grain pattern stay intact.
    public func apply(_ recipe: Recipe) {
        adjustments = recipe.applying(to: adjustments)
    }

    /// Writes any pending change now. Call when the editor may not come back (its window going
    /// inactive, the app quitting).
    public func save() {
        pendingSave?.cancel()
        pendingSave = nil
        store.update(photo.id, adjustments: adjustments)
    }

    /// Saves and lets go of the photo's RAW decoder. Call when the editor goes away.
    public func close() {
        save()
        store.renderService.close(url)
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
