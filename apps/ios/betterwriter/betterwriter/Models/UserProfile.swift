import Foundation
import SwiftData

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var installDate: Date
    var currentStreak: Int
    var longestStreak: Int
    var totalWordsWritten: Int
    var onboardingDay0Done: Bool
    var onboardingDay1Done: Bool

    init(
        id: UUID = UUID(),
        installDate: Date = Date(),
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        totalWordsWritten: Int = 0,
        onboardingDay0Done: Bool = false,
        onboardingDay1Done: Bool = false
    ) {
        self.id = id
        self.installDate = installDate
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.totalWordsWritten = totalWordsWritten
        self.onboardingDay0Done = onboardingDay0Done
        self.onboardingDay1Done = onboardingDay1Done
    }
}
