import CoreTransferable
import EmulsionCore
import Foundation
import UniformTypeIdentifiers

public struct RecipeTransfer: Transferable {
    public let recipe: Recipe

    public init(recipe: Recipe) { self.recipe = recipe }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            SentTransferredFile(try item.exportFile())
        }
    }

    func exportFile() throws -> URL {
        // Unique directories keep concurrent shares independent; the system purges temporary files.
        let folder = URL.temporaryDirectory.appending(path: "EmulsionLook-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Emulsion Look.json")
        try recipe.encoded().write(to: url, options: .atomic)
        return url
    }
}
