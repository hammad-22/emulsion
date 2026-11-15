import CoreTransferable
import EmulsionCore
import Foundation
import UniformTypeIdentifiers

public struct RecipeTransfer: Transferable {
    public let recipe: Recipe

    private static let sharingFolderPrefix = "EmulsionLook-"
    private static let sharedFileName = "Emulsion Look.json"

    public init(recipe: Recipe) { self.recipe = recipe }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            SentTransferredFile(try item.exportFile())
        }
    }

    func exportFile() throws -> URL {
        // A unique folder per share keeps concurrent shares independent.
        let folder = URL.temporaryDirectory.appending(path: "\(Self.sharingFolderPrefix)\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: Self.sharedFileName)
        try recipe.encoded().write(to: url, options: .atomic)
        return url
    }
}
