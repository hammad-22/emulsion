import EmulsionKit
import SwiftUI

struct LibrarySelection: Equatable {
    var isActive = false
    var photos: Set<PhotoRecord.ID> = []
    var pendingDeletion: Set<PhotoRecord.ID> = []

    var title: Text {
        photos.isEmpty ? Text("Select Photos") : Text("\(photos.count) Selected")
    }

    mutating func toggle(_ id: PhotoRecord.ID) {
        if photos.remove(id) == nil { photos.insert(id) }
    }

    mutating func begin(with id: PhotoRecord.ID) {
        isActive = true
        photos = [id]
    }
}
