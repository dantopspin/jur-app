// Shapes of the data the app reads. Dates stay ISO strings and are parsed where shown.
import Foundation

enum Gender: String, Codable { case woman, man }
enum InterestedIn: String, Codable, CaseIterable { case women, men, everyone }
enum ProfileMode: String, Codable, CaseIterable { case dating, buddy, both }
enum Verification: String, Codable { case unverified = "none", pending, approved, rejected }

struct MyProfile: Decodable, Identifiable, Equatable {
    let id: UUID
    let memberNo: Int
    let name: String
    let birthdate: String
    let gender: Gender
    let interestedIn: InterestedIn
    let ageMin: Int?
    let ageMax: Int?
    let city: String
    let bio: String?
    let nextChallenge: String?
    let photos: [String]
    let locale: String?
    let referralCode: String
    let verificationStatus: Verification
    let isHost: Bool
    let hidden: Bool
    let banned: Bool
    let mode: ProfileMode?
    let travelCity: String?
    let travelUntil: String?
    let cityNo: Int?
}

struct Limits: Decodable, Equatable {
    let pro: Bool
    let proUntil: String?
    let likesLeft: Int?
    let supersLeft: Int
    let boostCredits: Int
    let freeBoostAvailable: Bool
    let boostedUntil: String?
    let streakDays: Int
}

/// "№0042"
func formatMemberNo(_ n: Int) -> String { "№" + String(format: "%04d", n) }
