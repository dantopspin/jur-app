// Everything onboarding has collected so far. Saved on the device as people answer,
// so closing the app mid-way resumes where they were (photos already uploaded stay
// attached). Deleted once the profile exists or the person signs out. Nothing here is
// sent anywhere until the profile is created.
import Foundation

struct OnboardingDraft: Codable, Equatable {
    /// The questions, in order. `issued` is the end: the profile exists, the passport is shown.
    enum Step: Int, Codable, CaseIterable, Comparable {
        case name, birth, identity, city, sports, photos, about, issued
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
        /// The questions the progress line counts (everything before `issued`).
        static var questions: Int { Step.issued.rawValue }
    }

    var step: Step = .name
    var name = ""
    /// The name came from Sign in with Apple (shown as a hint under the field).
    var nameFromApple = false
    var birth = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    /// The person has moved past the birthdate step, so their age can be shown.
    var birthConfirmed = false
    var gender: Gender?
    var interested: InterestedIn?
    var city: String?
    var picked: [String: Level] = [:]
    var photos: [String] = []
    var challenge = ""
    var bio = ""

    var age: Int { Calendar.current.dateComponents([.year], from: birth, to: .now).year ?? 0 }

    /// A first draft: the name Apple shared, if any.
    static func fresh() -> OnboardingDraft {
        var d = OnboardingDraft()
        if let name = UserDefaults.standard.string(forKey: "jur.prefillName"), !name.isEmpty {
            d.name = name
            d.nameFromApple = true
        }
        return d
    }

    // MARK: storage (one draft per account)

    private static func key(_ owner: String) -> String { "jur.onboarding.\(owner)" }

    static func load(for owner: String) -> OnboardingDraft? {
        guard let data = UserDefaults.standard.data(forKey: key(owner)),
              var draft = try? JSONDecoder().decode(OnboardingDraft.self, from: data) else { return nil }
        // A saved draft never resumes on the end screen: that one belongs to a profile that exists.
        if draft.step == .issued { draft.step = .about }
        return draft
    }

    func save(for owner: String) {
        guard step != .issued, let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(owner))
    }

    static func clear(for owner: String) {
        UserDefaults.standard.removeObject(forKey: key(owner))
    }
}
