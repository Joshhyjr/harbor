import XCTest
@testable import HarborCore

final class ReminderTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Halifax")!
        return result
    }
    private func date(_ day: Int, hour: Int = 12) -> Date { date(2026, 10, day, hour: hour) }
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func ledger() -> FinanceData {
        var data = FinanceData.demo()
        data.isDemo = false; data.transactions = []; data.bills = []
        return data
    }
    private func bill(in data: FinanceData, due: Date) -> Bill {
        Bill(name: "Private merchant 123", amount: 48_00, due: due, accountID: data.accounts[0].id, categoryID: data.categories[0].id)
    }

    // Idempotency, missed days, and clock rollback must never create extra daily progress.
    func testStreakCountsDaysRatherThanTapsAndKeepsPersonalBest() throws {
        var streak = CheckInStreak()
        XCTAssertTrue(streak.complete(on: date(25), calendar: calendar))
        XCTAssertFalse(streak.complete(on: date(25, hour: 23), calendar: calendar))
        XCTAssertTrue(streak.complete(on: date(26), calendar: calendar))
        XCTAssertEqual(streak.count, 2)
        let before = streak
        XCTAssertFalse(streak.complete(on: date(24), calendar: calendar))
        XCTAssertEqual(streak, before)
        XCTAssertEqual(streak.current(on: date(27), calendar: calendar), 2)
        XCTAssertEqual(streak.current(on: date(28), calendar: calendar), 0)
        XCTAssertTrue(streak.complete(on: date(29), calendar: calendar))
        XCTAssertEqual(streak.count, 1); XCTAssertEqual(streak.best, 2); XCTAssertEqual(streak.total, 3)
        try streak.validate()
    }

    // DST and year boundaries are consecutive local days even when they are not 24 hours apart.
    func testStreakAcrossDaylightSavingAndYearBoundary() {
        var streak = CheckInStreak()
        let beforeDST = date(2026, 3, 7)
        let afterDST = date(2026, 3, 8)
        XCTAssertEqual(afterDST.timeIntervalSince(beforeDST), 23 * 3600)
        XCTAssertTrue(streak.complete(on: beforeDST, calendar: calendar))
        XCTAssertTrue(streak.complete(on: afterDST, calendar: calendar))
        XCTAssertEqual(streak.count, 2)
        streak = CheckInStreak()
        XCTAssertTrue(streak.complete(on: date(2026, 12, 31), calendar: calendar))
        XCTAssertTrue(streak.complete(on: date(2027, 1, 1), calendar: calendar))
        XCTAssertEqual(streak.count, 2)
    }

    // A new optional field must survive encryption/restore while old ledger JSON still loads.
    func testCheckInBackupRoundTripAndLegacyCompatibility() throws {
        var data = ledger()
        let legacy = try JSONEncoder().encode(data)
        XCTAssertNil(try JSONDecoder().decode(FinanceData.self, from: legacy).checkInStreak)
        let original = data
        var streak = CheckInStreak()
        for day in 1...7 { streak.complete(on: date(day), calendar: calendar) }
        data.checkInStreak = streak
        data.version = data.requiredVersion
        try data.validate()
        let key = String(repeating: "AB", count: 32)
        let restored = try PortableBackup.decode(PortableBackup.encrypt(data, recoveryKey: key), recoveryKey: key)
        XCTAssertEqual(restored, data)
        XCTAssertEqual(restored.checkInStreak?.milestone, 7)
        var financialRecords = restored; financialRecords.checkInStreak = nil
        XCTAssertEqual(financialRecords, original)
        var invalid = data
        invalid.checkInStreak?.best = 1
        XCTAssertThrowsError(try invalid.validate())
    }

    // Opt-out, demo mode, and invalid reminder times must all produce an empty schedule.
    func testRemindersDefaultOffAndNeverScheduleDemoRecords() {
        var data = ledger(); data.bills = [bill(in: data, due: date(27))]
        XCTAssertTrue(ReminderPlanner.plan(data: data, attentionCount: 1, options: ReminderOptions(), now: date(25), calendar: calendar).isEmpty)
        let all = ReminderOptions(failures: true, bills: true, reviews: true, checkIns: true)
        data.isDemo = true
        XCTAssertTrue(ReminderPlanner.plan(data: data, attentionCount: 1, options: all, now: date(25), calendar: calendar).isEmpty)
        data.isDemo = false
        var invalid = all; invalid.hour = 24
        XCTAssertTrue(ReminderPlanner.plan(data: data, attentionCount: 1, options: invalid, now: date(25), calendar: calendar).isEmpty)
    }

    // Group bills per day; unconfirmed schedules and private values must not leak into reminders.
    func testUpcomingBillsAggregateAndExcludeUncertainSchedules() {
        var data = ledger()
        data.bills = [bill(in: data, due: date(27)), bill(in: data, due: date(27))]
        var uncertain = bill(in: data, due: date(28)); uncertain.needsScheduleReview = true
        data.bills.append(uncertain)
        let plan = ReminderPlanner.plan(data: data, attentionCount: 0, options: ReminderOptions(bills: true), now: date(25), calendar: calendar)
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan.map { calendar.component(.day, from: $0.date) }, [26, 27])
        XCTAssertTrue(plan.allSatisfy { $0.date > date(25) && !$0.body.contains("Private merchant") && !$0.body.contains("48") })
    }

    // A changed/deleted/paid occurrence must replace its old reminder plan, never leave the old due day.
    func testBillScheduleReplansAfterPaymentAndDeletion() throws {
        var data = ledger()
        let original = bill(in: data, due: date(27)); data.bills = [original]
        let options = ReminderOptions(bills: true)
        XCTAssertEqual(ReminderPlanner.plan(data: data, attentionCount: 0, options: options, now: date(27, hour: 8), calendar: calendar).count, 1)
        try data.payBill(original.id, expectedDue: original.due, now: date(27, hour: 9))
        let after = ReminderPlanner.plan(data: data, attentionCount: 0, options: options, now: date(27, hour: 10), calendar: calendar)
        XCTAssertFalse(after.contains { calendar.isDate($0.date, inSameDayAs: date(27)) })
        data.bills = []
        XCTAssertTrue(ReminderPlanner.plan(data: data, attentionCount: 0, options: options, now: date(27), calendar: calendar).isEmpty)
    }

    // Completing today cancels its check-in reminder, and cleared review work cancels review nudges.
    func testDailyReminderCombiningAndCompletion() {
        var data = ledger()
        let options = ReminderOptions(reviews: true, checkIns: true)
        let plan = ReminderPlanner.plan(data: data, attentionCount: 1, options: options, now: date(25), calendar: calendar)
        XCTAssertEqual(plan.count, 7)
        XCTAssertEqual(Set(plan.map(\.id)).count, 7)
        var streak = CheckInStreak(); streak.complete(on: date(25), calendar: calendar)
        data.checkInStreak = streak
        let after = ReminderPlanner.plan(data: data, attentionCount: 0, options: options, now: date(25), calendar: calendar)
        XCTAssertEqual(after.count, 6)
        XCTAssertFalse(after.contains { calendar.isDate($0.date, inSameDayAs: date(25)) })
        XCTAssertTrue(ReminderPlanner.plan(data: data, attentionCount: 0, options: ReminderOptions(reviews: true), now: date(25), calendar: calendar).isEmpty)
    }

    // Never backfill missed notifications, and keep the pending schedule below its reserved capacity.
    func testPastTimesOverdueDigestAndRequestBudget() {
        var data = ledger()
        data.bills = [bill(in: data, due: date(24)), bill(in: data, due: date(23))]
        let options = ReminderOptions(bills: true, checkIns: true)
        var plan = ReminderPlanner.plan(data: data, attentionCount: 0, options: options, now: date(25, hour: 20), calendar: calendar)
        XCTAssertEqual(plan.filter { $0.id.hasPrefix("bill.overdue") }.count, 1)
        XCTAssertTrue(plan.allSatisfy { $0.date > date(25, hour: 20) })
        data.bills = (1...60).map { bill(in: data, due: calendar.date(byAdding: .day, value: $0, to: date(25))!) }
        plan = ReminderPlanner.plan(data: data, attentionCount: 0, options: options, now: date(25), calendar: calendar)
        XCTAssertLessThanOrEqual(plan.count, 48)
        XCTAssertTrue(plan.allSatisfy { $0.date < calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: date(25)))! })
    }
}
