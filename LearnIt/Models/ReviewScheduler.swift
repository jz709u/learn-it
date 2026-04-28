import Foundation

enum StudyMode: String, CaseIterable, Identifiable {
    case due = "Due"
    case all = "All"

    var id: String { rawValue }
}

enum ReviewRating: String, CaseIterable, Identifiable {
    case again = "Again"
    case hard = "Hard"
    case good = "Good"
    case easy = "Easy"

    var id: String { rawValue }

    var tintName: String {
        switch self {
        case .again: return "red"
        case .hard: return "orange"
        case .good: return "blue"
        case .easy: return "green"
        }
    }
}

struct ReviewState: Codable, Hashable {
    var repetitions: Int
    var intervalDays: Int
    var easeFactor: Double
    var dueDate: Date
    var lastReviewedAt: Date?
    var lapses: Int

    static func new(now: Date) -> ReviewState {
        ReviewState(
            repetitions: 0,
            intervalDays: 0,
            easeFactor: 2.5,
            dueDate: now,
            lastReviewedAt: nil,
            lapses: 0
        )
    }

    func isDue(at date: Date) -> Bool {
        dueDate <= date
    }
}

enum ReviewScheduler {
    static func nextState(from state: ReviewState?, rating: ReviewRating, now: Date = .now) -> ReviewState {
        var current = state ?? .new(now: now)

        switch rating {
        case .again:
            current.repetitions = 0
            current.intervalDays = 0
            current.easeFactor = max(1.3, current.easeFactor - 0.2)
            current.dueDate = now.addingTimeInterval(10 * 60)
            current.lapses += 1

        case .hard:
            current.repetitions += 1
            current.easeFactor = max(1.3, current.easeFactor - 0.15)
            current.intervalDays = max(1, hardInterval(for: current))
            current.dueDate = Calendar.current.date(byAdding: .day, value: current.intervalDays, to: now) ?? now

        case .good:
            current.repetitions += 1
            current.intervalDays = max(1, goodInterval(for: current))
            current.dueDate = Calendar.current.date(byAdding: .day, value: current.intervalDays, to: now) ?? now

        case .easy:
            current.repetitions += 1
            current.easeFactor += 0.15
            current.intervalDays = max(2, easyInterval(for: current))
            current.dueDate = Calendar.current.date(byAdding: .day, value: current.intervalDays, to: now) ?? now
        }

        current.lastReviewedAt = now
        return current
    }

    private static func goodInterval(for state: ReviewState) -> Int {
        switch state.repetitions {
        case 1: return 1
        case 2: return 3
        default:
            return Int((Double(max(state.intervalDays, 1)) * state.easeFactor).rounded())
        }
    }

    private static func hardInterval(for state: ReviewState) -> Int {
        switch state.repetitions {
        case 1: return 1
        case 2: return 2
        default:
            let scaled = Double(max(state.intervalDays, 1)) * 1.2
            return Int(scaled.rounded(.up))
        }
    }

    private static func easyInterval(for state: ReviewState) -> Int {
        switch state.repetitions {
        case 1: return 4
        case 2: return 7
        default:
            let scaled = Double(max(state.intervalDays, 1)) * (state.easeFactor + 0.3)
            return Int(scaled.rounded())
        }
    }
}
