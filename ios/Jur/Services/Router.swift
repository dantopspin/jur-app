// Where a notification tap (or a link) should take you. The server puts a path in
// each push's data: "/chat/<match>", "/likes", "/event/<id>", "/discover", "/picks".
import Foundation
import Observation

@MainActor
@Observable
final class Router {
    static let shared = Router()

    enum Destination: Equatable {
        case chat(UUID), likes, event(UUID), discover, matches, picks
    }

    var pending: Destination?

    func open(path: String) {
        let parts = path.split(separator: "/").map(String.init)
        switch (parts.first ?? "", parts.dropFirst().first.flatMap { UUID(uuidString: $0) }) {
        case ("chat", let id?): pending = .chat(id)
        case ("event", let id?): pending = .event(id)
        case ("likes", _): pending = .likes
        case ("picks", _): pending = .picks
        case ("matches", _): pending = .matches
        default: pending = .discover
        }
    }
}
