import CoreTransferable
import EmulsionCore
import Foundation
import UniformTypeIdentifiers

public struct RecipeTransfer: Transferable {
    public let recipe: Recipe

    private static let sharingFolderPrefix = "EmulsionLook-"
    /// The name the recipient sees.
    private static let sharedFileName = "Emulsion Look.json"

    public init(recipe: Recipe) { self.recipe = recipe }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            SentTransferredFile(try item.exportFile())
        }
    }

    func exportFile() throws -> URL {
        // Unique directories keep concurrent shares independent; the system purges temporary files.
        let folder = URL.temporaryDirectory.appending(path: "\(Self.sharingFolderPrefix)\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: Self.sharedFileName)
        try recipe.encoded().write(to: url, options: .atomic)
        return url
    }
}
