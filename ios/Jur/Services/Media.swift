// Photo uploads: profile photos go to the public "photos" bucket (the profile keeps
// their public URLs); verification selfies go to the private "verification" bucket.
import PhotosUI
import Supabase
import SwiftUI
import UIKit

enum Media {
    /// Downscales to 1600 px on the long edge and re-encodes as JPEG (strips location metadata).
    static func jpeg(from data: Data, maxSide: CGFloat = 1600) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.82)
    }

    static func uploadProfilePhoto(_ item: PhotosPickerItem, userId: UUID) async throws -> String {
        guard let raw = try await item.loadTransferable(type: Data.self), let jpeg = jpeg(from: raw) else {
            throw ServerError(code: "bad_image")
        }
        return try await uploadProfilePhoto(jpeg, userId: userId)
    }

    static func uploadProfilePhoto(_ jpeg: Data, userId: UUID) async throws -> String {
        let path = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await supabase.storage.from("photos")
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
        return try supabase.storage.from("photos").getPublicURL(path: path).absoluteString
    }

    static func uploadSelfie(_ jpeg: Data, userId: UUID) async throws -> String {
        let path = "\(userId.uuidString.lowercased())/selfie-\(UUID().uuidString.lowercased()).jpg"
        _ = try await supabase.storage.from("verification")
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
        return path
    }
}

/// The sports catalog, loaded once per launch.
@MainActor
@Observable
final class SportsCatalog {
    private(set) var all: [Sport] = []

    func load() async {
        guard all.isEmpty else { return }
        all = (try? await Backend.sports()) ?? []
    }

    func sport(_ code: String) -> Sport? { all.first { $0.code == code } }
    func label(_ code: String) -> String {
        guard let s = sport(code) else { return code }
        return "\(s.emoji) \(s.name)"
    }
}
