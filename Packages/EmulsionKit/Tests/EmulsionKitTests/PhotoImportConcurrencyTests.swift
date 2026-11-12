import EmulsionCore
import Foundation
import Testing

@testable import EmulsionKit

@MainActor
struct PhotoImportConcurrencyTests {
    @Test func overlappingImportsPreserveInterveningEditsAndDeletions() async throws {
        let library = TestLibrary()
        let edited = try await library.store.add(TestPhoto.jpeg)
        let deleted = try await library.store.add(TestPhoto.jpeg)
        let gate = ImportGate()
        let store = PhotoStore(
            folder: library.folder, renderService: library.renderService,
            importer: OriginalImporter { worker in
                worker.assertIsolated()
                await gate.pause()
            })
        let first = Task { try await store.add(TestPhoto.jpeg) }
        let second = Task { try await store.add(TestPhoto.jpeg) }
        await gate.waitForEntries(2)
        #expect(Set(store.photos.map(\.id)) == Set([edited.id, deleted.id]), "uncommitted imports stay invisible")
        var edit = edited.adjustments
        edit.exposure = 1.25
        store.update(edited.id, adjustments: edit)
        await store.delete(deleted.id)
        await gate.release()
        let imported = try await [first.value, second.value]

        let reopened = library.reopened()
        #expect(Set(reopened.photos.map(\.id)) == Set([edited.id] + imported.map(\.id)))
        #expect(reopened.photo(edited.id)?.adjustments == edit)
        for photo in imported {
            #expect(photo.adjustments == .defaults(for: photo.id))
            #expect(try Data(contentsOf: store.url(for: photo)) == TestPhoto.jpeg)
        }
    }

    @Test func cancellationAfterPreparationRemovesOnlyItsOwnFiles() async throws {
        let library = TestLibrary()
        let kept = try await library.store.add(TestPhoto.jpeg)
        let saved = try Data(contentsOf: library.store.indexURL)
        let gate = ImportGate()
        let store = PhotoStore(
            folder: library.folder, renderService: library.renderService,
            importer: OriginalImporter { _ in await gate.pause() })
        let task = Task { try await store.addSamples() }
        await gate.waitForEntries(1)
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(store.photos == [kept])
        #expect(try Data(contentsOf: store.indexURL) == saved)
        #expect(try Data(contentsOf: store.url(for: kept)) == TestPhoto.jpeg)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: library.folder.path).sorted() == [kept.fileName, "library.json"].sorted())
    }

    @Test func cancellingOneOverlappingImportKeepsTheOther() async throws {
        let library = TestLibrary()
        let gate = ImportGate()
        let store = PhotoStore(
            folder: library.folder, renderService: library.renderService,
            importer: OriginalImporter { _ in await gate.pause() })
        let cancelled = Task { try await store.add(TestPhoto.jpeg) }
        let successful = Task { try await store.add(TestPhoto.jpeg) }
        await gate.waitForEntries(2)
        cancelled.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let kept = try await successful.value
        #expect(store.photos == [kept])
        #expect(library.reopened().photos == [kept])
        #expect(try Data(contentsOf: store.url(for: kept)) == TestPhoto.jpeg)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: library.folder.path).sorted() == [kept.fileName, "library.json"].sorted())
    }

    @Test func failedCommitKeepsInterveningEditsAndEveryExistingOriginal() async throws {
        let library = TestLibrary()
        let kept = try await library.store.add(TestPhoto.jpeg)
        let gate = ImportGate()
        let store = PhotoStore(
            folder: library.folder, renderService: library.renderService,
            importer: OriginalImporter { _ in await gate.pause() })
        let task = Task { try await store.addSamples() }
        await gate.waitForEntries(1)
        var edit = kept.adjustments
        edit.warmth = 0.5
        store.update(kept.id, adjustments: edit)
        let saved = try Data(contentsOf: store.indexURL)
        try FileManager.default.removeItem(at: store.indexURL)
        try FileManager.default.createDirectory(at: store.indexURL, withIntermediateDirectories: false)
        await gate.release()
        await #expect(throws: EmulsionError.librarySaveFailed) { try await task.value }

        #expect(store.photo(kept.id)?.adjustments == edit)
        #expect(store.photos.count == 1)
        #expect(try Data(contentsOf: store.url(for: kept)) == TestPhoto.jpeg)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: library.folder.path).sorted() == [kept.fileName, "library.json"].sorted())
        try FileManager.default.removeItem(at: store.indexURL)
        try saved.write(to: store.indexURL)
        #expect(library.reopened().photo(kept.id)?.adjustments == edit)
    }

    @Test func partialPreparationFailureCleansOnlyImportOwnedOriginals() async throws {
        let library = TestLibrary()
        let kept = try await library.store.add(TestPhoto.jpeg)
        let importer = OriginalImporter()
        await #expect(throws: EmulsionError.unsupportedPhoto) {
            try await importer.prepare([.data(TestPhoto.jpeg, fileExtension: nil), .data(Data(), fileExtension: nil)], in: library.folder)
        }
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: library.folder.path).sorted() == [kept.fileName, "library.json"].sorted())
        #expect(try Data(contentsOf: library.store.url(for: kept)) == TestPhoto.jpeg)
    }

    @Test func fileReadFailureIsTypedAndDoesNotLeaveStagingFiles() async throws {
        let library = TestLibrary()
        _ = library.store
        await #expect(throws: EmulsionError.librarySaveFailed) {
            try await OriginalImporter().prepare([.file(library.folder.appending(path: "missing.jpg"))], in: library.folder)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.folder.path).isEmpty)
    }
}

/// Tests choose exactly when prepared originals may proceed to index commit.
private actor ImportGate {
    private var entries = 0
    private var paused: [CheckedContinuation<Void, Never>] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func pause() async {
        entries += 1
        let ready = observers.filter { entries >= $0.0 }
        observers.removeAll { entries >= $0.0 }
        for (_, continuation) in ready { continuation.resume() }
        await withCheckedContinuation { paused.append($0) }
    }

    func waitForEntries(_ count: Int) async {
        guard entries < count else { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }

    func release() {
        let waiting = paused
        paused = []
        for continuation in waiting { continuation.resume() }
    }
}
