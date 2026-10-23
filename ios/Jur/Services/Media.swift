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

    /// The photo plus a 480 px copy beside it (`<id>_t.jpg`) for avatars, grids and lists.
    /// Names are never reused, so both are cached for a year.
    static func uploadProfilePhoto(_ jpeg: Data, userId: UUID) async throws -> String {
        let id = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased())"
        let bucket = supabase.storage.from("photos")
        let options = FileOptions(cacheControl: "31536000", contentType: "image/jpeg")
        _ = try await bucket.upload("\(id).jpg", data: jpeg, options: options)
        if let thumb = Media.jpeg(from: jpeg, maxSide: 480) {
            // A missing copy only means the original is used; never fail the upload for it.
            _ = try? await bucket.upload("\(id)_t.jpg", data: thumb, options: options)
        }
        let url = try bucket.getPublicURL(path: "\(id).jpg")
        ImageLoader.shared.seed(jpeg, for: url)
        return url.absoluteString
    }

    /// Photos taken off a profile (or uploaded and then discarded) are removed from storage
    /// with their small copies, so they stop being reachable by link. Only files in your
    /// own folder can be removed (storage rules), and a failure just leaves the file.
    static func deletePhotos(_ urls: some Sequence<String>) async {
        let marker = "/storage/v1/object/public/photos/"
        let paths = urls.compactMap { url -> [String]? in
            guard let r = url.range(of: marker) else { return nil }
            let path = String(url[r.upperBound...])
            guard path.hasSuffix(".jpg") else { return [path] }
            return [path, String(path.dropLast(4)) + "_t.jpg"]
        }.flatMap { $0 }
        guard !paths.isEmpty else { return }
        _ = try? await supabase.storage.from("photos").remove(paths: paths)
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
