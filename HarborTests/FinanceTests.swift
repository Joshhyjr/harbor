import XCTest
@testable import HarborCore

// These tests exercise financial invariants, rather than reproducing screen implementation details.
final class FinanceTests: XCTestCase {
    // Emoji is one grapheme, even when flags, modifiers or joiners require several Unicode scalars.
    func testCustomEmojiIconValidation() {
        for emoji in ["🐾", "🏡", "❤️", "❤", "🇨🇦", "👨🏽‍💻", "👨‍👩‍👧‍👦", "1️⃣", "☕️"] {
            XCTAssertEqual(HarborIcon.emoji(in: emoji), emoji)
        }
        XCTAssertEqual(HarborIcon.emoji(in: "  🐾\n"), "🐾")
        for invalid in ["", " ", "1", "#", "a", "coffee", "house", "🐾🏡", "a🐾"] {
            XCTAssertNil(HarborIcon.emoji(in: invalid))
        }
    }
    // Existing symbol strings and custom emoji survive both legacy JSON and encrypted portable backups.
    func testEmojiIconsSurviveBackupsWithoutChangingMoney() throws {
        var data = FinanceData.demo()
        let before = data.netWorth
        data.categories[0].symbol = "👨🏽‍💻"
        data.goals[0].symbol = "🇨🇦"
        try data.validate()
        let decoded = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded, data)
        let key = PortableBackup.recoveryKey()
        let restored = try PortableBackup.decode(PortableBackup.encrypt(data, recoveryKey: key), recoveryKey: key)
        XCTAssertEqual(restored, data)
        XCTAssertEqual(restored.netWorth, before)
        XCTAssertEqual(restored.categories[1].symbol, "basket")
    }
    func testDecimalInputNeverRounds() {
        XCTAssertEqual(Money.parse("12.34"), 1234)
        XCTAssertEqual(Money.parse("0.01"), 1)
        XCTAssertEqual(Money.parse("-12.34", allowNegative: true), -1234)
        for invalid in ["1.999", "1e3", "NaN", "", "-2", "1,000", "1.2.3"] { XCTAssertNil(Money.parse(invalid)) }
    }
    func testDemoIsConsistentAndBackupRoundTrips() throws {
        let data = FinanceData.demo()
        try data.validate()
        let decoded = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(data, decoded)
        XCTAssertEqual(data.goals.reduce(0) { $0 + $1.saved }, 4_265_000)
    }
    func testExpenseEditAndDeleteRecalculateBalances() throws {
        var data = FinanceData.demo()
        let account = data.accounts[0].id
        let before = data.balance(account)
        let entry = Transaction(merchant: "Test", amount: 10_01, kind: .expense, date: Date(), accountID: account, categoryID: data.categories[1].id)
        let spending = data.total(.expense, in: Date())
        data.transactions.append(entry)
        XCTAssertEqual(data.balance(account), before - 1001)
        XCTAssertEqual(data.total(.expense, in: Date()), spending + 1001)
        data.transactions[data.transactions.count - 1].amount = 2002
        XCTAssertEqual(data.balance(account), before - 2002)
        data.transactions.removeAll { $0.id == entry.id }
        XCTAssertEqual(data.balance(account), before)
        try data.validate()
    }
    func testGoalAllocationsDoNotChangeNetWorth() throws {
        var data = FinanceData.demo()
        let before = data.netWorth
        data.goals[0].saved -= 10000
        XCTAssertEqual(data.netWorth, before)
        try data.validate()
        data.goals[0].saved += 10001
        XCTAssertThrowsError(try data.validate())
    }
    func testCombinedAllocationsCannotExceedFundingAccount() throws {
        var data = FinanceData.demo()
        data.goals[0].saved -= 100
        data.goals[1].saved += 101
        XCTAssertThrowsError(try data.validate())
        data.goals[1].saved -= 1
        try data.validate()
    }
    func testExpenseCannotConsumeReservedSavings() {
        var data = FinanceData.demo()
        data.transactions.append(Transaction(merchant: "Test", amount: 1, kind: .expense, date: Date(), accountID: data.accounts[1].id, categoryID: data.categories[1].id))
        XCTAssertThrowsError(try data.validate())
    }
    func testBillPaymentIsAtomicAndMovesDueDate() throws {
        var data = FinanceData.demo()
        let bill = data.bills[0]
        let before = data.balance(bill.accountID)
        let count = data.transactions.count
        try data.payBill(bill.id)
        XCTAssertEqual(data.transactions.count, count + 1)
        XCTAssertEqual(data.balance(bill.accountID), before - bill.amount)
        XCTAssertEqual(data.bills[0].due, Calendar.current.date(byAdding: .month, value: 1, to: bill.due))
        data.bills[0].accountID = data.accounts[1].id
        data.bills[0].lastPaidAt = nil // Exercise balance validation separately from duplicate protection.
        let snapshot = data
        XCTAssertThrowsError(try data.payBill(bill.id))
        XCTAssertEqual(data, snapshot)
    }
    // One tap records one occurrence; persisted completion must not prevent the next recurrence.
    func testPaidBillPersistsAndRejectsDuplicateOccurrence() throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!
        var data = FinanceData.demo(now: now)
        let bill = data.bills[0]
        let count = data.transactions.count
        try data.payBill(bill.id, expectedDue: bill.due, now: now)
        XCTAssertEqual(data.transactions.count, count + 1)
        XCTAssertEqual(data.bills[0].lastPaidAt, now)
        XCTAssertTrue(data.bills[0].isPaymentComplete(on: now))
        let completed = data
        XCTAssertThrowsError(try data.payBill(bill.id, expectedDue: bill.due, now: now))
        XCTAssertEqual(data, completed)
        data = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(data))
        XCTAssertTrue(data.bills[0].isPaymentComplete(on: now.addingTimeInterval(60)))
        let nextDue = data.bills[0].due
        XCTAssertFalse(data.bills[0].isPaymentComplete(on: nextDue))
        XCTAssertThrowsError(try data.payBill(bill.id, expectedDue: bill.due, now: nextDue))
        XCTAssertEqual(data, completed)
        try data.payBill(bill.id, expectedDue: nextDue, now: nextDue)
        XCTAssertEqual(data.transactions.count, count + 2)
        XCTAssertTrue(data.bills[0].isPaymentComplete(on: nextDue))
    }
    func testOldBillsDecodeWithoutCompletionMetadata() throws {
        let data = FinanceData.demo()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
        var bills = try XCTUnwrap(json["bills"] as? [[String: Any]])
        for index in bills.indices { bills[index].removeValue(forKey: "lastPaidAt") }
        json["bills"] = bills
        let restored = try JSONDecoder().decode(FinanceData.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(restored.bills.allSatisfy { $0.lastPaidAt == nil && !$0.isPaymentComplete() })
    }
    func testInvalidBackupReferencesAndVersionsAreRejected() throws {
        var data = FinanceData.demo()
        data.transactions[0].accountID = UUID()
        XCTAssertThrowsError(try data.validate())
        // Statement history uses version 3; future versions must still be rejected.
        data = .demo(); data.version = 4
        XCTAssertThrowsError(try data.validate())
        data = .demo(); data.accounts.append(data.accounts[0])
        XCTAssertThrowsError(try data.validate())
    }
    func testExtremeImportedBalanceIsRejectedWithoutOverflow() {
        var data = FinanceData.demo()
        data.accounts[0].openingBalance = Int.min
        XCTAssertThrowsError(try data.validate())
        data.accounts[0].openingBalance = Int.max
        XCTAssertThrowsError(try data.validate())
    }
    func testMonthsSeparateIncomeAndExpense() throws {
        var data = FinanceData.demo()
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        data.transactions.append(Transaction(merchant: "Prior", amount: 333, kind: .expense, date: lastMonth, accountID: data.accounts[0].id, categoryID: data.categories[1].id))
        XCTAssertEqual(data.total(.expense, in: lastMonth), 333)
        XCTAssertEqual(data.total(.income, in: Date()), 645000)
        XCTAssertEqual(data.total(.expense, in: Date(), category: data.categories[1].id), 15263)
    }
}
