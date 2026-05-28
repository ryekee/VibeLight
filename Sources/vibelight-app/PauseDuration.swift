import Foundation

enum PauseDuration {
    case thirtyMinutes
    case oneHour
    case untilTomorrow

    var label: String {
        switch self {
        case .thirtyMinutes:  return "Pause for 30 minutes"
        case .oneHour:        return "Pause for 1 hour"
        case .untilTomorrow:  return "Pause until tomorrow"
        }
    }

    func resumeDate(now: Date) -> Date {
        switch self {
        case .thirtyMinutes:
            return now.addingTimeInterval(30 * 60)
        case .oneHour:
            return now.addingTimeInterval(60 * 60)
        case .untilTomorrow:
            let cal = Calendar.current
            var components = cal.dateComponents([.year, .month, .day], from: now)
            components.day = (components.day ?? 0) + 1
            components.hour = 6
            components.minute = 0
            components.second = 0
            return cal.date(from: components) ?? now.addingTimeInterval(8 * 60 * 60)
        }
    }
}
