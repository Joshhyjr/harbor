import Foundation

// Check-ins reward a deliberate review, independently of spending or notification permission.
struct CheckInStreak: Codable, Equatable {
    var lastCheckIn: Date?
    var count = 0
    var best = 0
    var total = 0

    func completed(on date: Date, calendar: Calendar = .current) -> Bool {
        lastCheckIn.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    }
    func current(on date: Date, calendar: Calendar = .current) -> Int {
        guard let lastCheckIn,
              let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastCheckIn), to: calendar.startOfDay(for: date)).day,
              (0...1).contains(days) else { return 0 }
        return count
    }
    @discardableResult mutating func complete(on date: Date, calendar: Calendar = .current) -> Bool {
        guard date.timeIntervalSince1970.isFinite else { return false }
        if let lastCheckIn {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastCheckIn), to: calendar.startOfDay(for: date)).day ?? 0
            // Repeated taps and moving the clock backwards cannot earn another day.
            guard days > 0 else { return false }
            count = days == 1 ? count + 1 : 1
        } else { count = 1 }
        lastCheckIn = date
        total += 1
        best = max(best, count)
        return true
    }
    func validate() throws {
        guard count >= 0, best >= count, total >= best, total <= 1_000_000,
              (lastCheckIn == nil) == (total == 0),
              total == 0 ? (count == 0 && best == 0) : (count > 0),
              lastCheckIn?.timeIntervalSince1970.isFinite ?? true else {
            throw FinanceError(message: "Invalid check-in history in backup.")
        }
    }
    var milestone: Int { [3, 7, 14, 30, 60, 100, 365].last(where: { best >= $0 }) ?? 0 }
    static func isMilestone(_ days: Int) -> Bool { [3, 7, 14, 30, 60, 100, 365].contains(days) }
}

// Preferences contain no financial records; every reminder category starts off.
struct ReminderOptions: Equatable {
    var failures = false
    var bills = false
    var reviews = false
    var checkIns = false
    var hour = 19
    var minute = 0
}
struct PlannedReminder: Equatable {
    var id: String
    var title: String
    var body: String
    var date: Date
}

// Plan from a saved ledger only. Generic payloads keep schedules and lock screens free of financial details.
enum ReminderPlanner {
    static func plan(data: FinanceData, attentionCount: Int, options: ReminderOptions,
                     now: Date = Date(), calendar: Calendar = .current) -> [PlannedReminder] {
        guard !data.isDemo, (0...23).contains(options.hour), (0...59).contains(options.minute) else { return [] }
        var result: [String: PlannedReminder] = [:]
        let today = calendar.startOfDay(for: now)
        func time(on day: Date) -> Date? {
            calendar.date(bySettingHour: options.hour, minute: options.minute, second: 0, of: day)
        }
        func add(_ kind: String, day: Date, title: String, body: String) {
            guard let date = time(on: day), date > now,
                  let horizon = calendar.date(byAdding: .day, value: 30, to: today), date < horizon else { return }
            // Aggregate bills sharing a date, so a busy day does not generate a banner for every bill.
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let id = "\(kind).\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
            result[id] = PlannedReminder(id: id, title: title, body: body, date: date)
        }
        let actionableBills = data.bills.filter { $0.needsScheduleReview != true }
        if options.bills {
            for bill in actionableBills {
                let due = calendar.startOfDay(for: bill.due)
                if let before = calendar.date(byAdding: .day, value: -1, to: due) {
                    add("bill.upcoming", day: before, title: "Upcoming bill", body: "A saved bill is due tomorrow. Open Harbor to check its schedule.")
                }
                add("bill.due", day: due, title: "Bill due today", body: "Check a saved bill in Harbor. This reminder does not confirm whether your bank has paid it.")
            }
            // One overdue digest, refreshed on the next unlock, avoids repeated failure-like bill alerts.
            if actionableBills.contains(where: { bill in
                calendar.startOfDay(for: bill.due) < today && !(bill.lastPaidAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
            }) {
                let day = (time(on: today) ?? now) > now ? today : calendar.date(byAdding: .day, value: 1, to: today)!
                add("bill.overdue", day: day, title: "Check a bill’s status", body: "A saved bill date has passed. Check its payment status in Harbor.")
            }
        }
        let needsReview = attentionCount > 0 || data.transactions.contains(where: \.needsReview) || data.bills.contains { $0.needsScheduleReview == true }
        // Refresh seven daily check-ins on each visit instead of scheduling an unbounded repeating nudge.
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let completed = (data.checkInStreak ?? CheckInStreak()).completed(on: day, calendar: calendar)
            if options.checkIns && !completed {
                add("checkin", day: day, title: "A moment for your finances", body: needsReview ? "Your daily check-in and a few items are ready to review in Harbor." : "Open Harbor for your daily check-in. A quick review is enough.")
            } else if options.reviews && needsReview {
                add("review", day: day, title: "Your review inbox is waiting", body: "Open Harbor when convenient to review items that need attention.")
            }
        }
        // Leave room for immediate capture/failure alerts within the system's pending-request budget.
        return Array(result.values).sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.prefix(48).map { $0 }
    }
}
