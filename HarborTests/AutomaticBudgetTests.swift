import XCTest
@testable import HarborCore

// Fixed calendar dates verify financial estimates independently of the device clock and locale.
final class AutomaticBudgetTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private func date(_ month: Int, _ day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }
    private func ledger() -> FinanceData {
        var data = FinanceData(isDemo: false)
        data.accounts = [Account(name: "CAD", openingBalance: 0)]
        data.categories = [Category(name: "Food", symbol: "basket", limit: 0), Category(name: "Transport", symbol: "tram", limit: 0)]
        return data
    }
    private func add(_ amount: Int, month: Int, category: Int = 0, kind: TransactionKind = .expense, to data: inout FinanceData) {
        data.transactions.append(Transaction(merchant: "Recorded activity", amount: amount, kind: kind, date: date(month, 15), accountID: data.accounts[0].id, categoryID: data.categories[category].id))
    }
    private func plan(_ data: FinanceData, month: Int = 10) -> AutomaticBudgets {
        AutomaticBudgets.calculate(data: data, month: date(month), now: date(10, 19), calendar: calendar)
    }
    func testAverageUsesPriorThreeMonthsAndNeverMutatesSavedLedger() {
        var data = ledger()
        for (month, amount) in [(6, 90_000), (7, 10_000), (8, 20_000), (9, 30_000), (10, 999_999), (11, 999_999)] {
            add(amount, month: month, to: &data)
        }
        let original = data
        let result = plan(data)
        XCTAssertEqual(result.limits[data.categories[0].id], 20_000)
        XCTAssertEqual(result.historyMonths["CAD"], 3)
        XCTAssertEqual(result.resolved(data.categories[0]).usesAutomaticBudget, true)
        XCTAssertEqual(data, original)
        // Current spending cannot inflate the limit to follow an overspend.
        add(999_999, month: 10, to: &data)
        XCTAssertEqual(plan(data), result)
    }
    func testEmptyCategoryMonthsCountAsZeroButMissingLedgerMonthsAreSkipped() {
        var data = ledger()
        add(10_000, month: 7, to: &data)
        add(40_000, month: 9, category: 1, to: &data)
        let result = plan(data)
        XCTAssertEqual(result.historyMonths["CAD"], 2)
        XCTAssertEqual(result.limits[data.categories[0].id], 5_000)
        XCTAssertEqual(result.limits[data.categories[1].id], 20_000)
    }
    func testNoHistoryAndSingleMonthAreExplicit() {
        var data = ledger()
        XCTAssertEqual(plan(data).limits[data.categories[0].id], 0)
        XCTAssertTrue(plan(data).note(for: data.categories[0]).contains("Needs prior-month history"))
        add(1_201, month: 9, to: &data)
        XCTAssertEqual(plan(data).limits[data.categories[0].id], 1_201)
        XCTAssertTrue(plan(data).note(for: data.categories[0]).contains("1 prior month"))
    }
    func testIncomeTransfersAndOtherCurrenciesDoNotBecomeSpending() {
        var data = ledger()
        add(10_000, month: 9, to: &data)
        add(99_000, month: 9, kind: .income, to: &data)
        add(70_000, month: 8, to: &data)
        data.transactions[data.transactions.count - 1].transferPairID = UUID()
        let usdAccount = Account(name: "USD", openingBalance: 0, currencyCode: "USD")
        let usdCategory = Category(name: "USD Food", symbol: "basket", limit: 0, currencyCode: "USD")
        data.accounts.append(usdAccount); data.categories.append(usdCategory)
        data.transactions.append(Transaction(merchant: "USD purchase", amount: 4_500, kind: .expense, date: date(7), accountID: usdAccount.id, categoryID: usdCategory.id))
        let result = plan(data)
        XCTAssertEqual(result.limits[data.categories[0].id], 10_000)
        XCTAssertEqual(result.historyMonths["CAD"], 1)
        XCTAssertEqual(result.historyMonths["USD"], 1)
        XCTAssertEqual(result.limits[usdCategory.id], 4_500)
    }
    func testManualLimitsIncludingExplicitZeroOverrideHistory() {
        var data = ledger()
        data.categories[0].limit = 12_345 // A positive legacy limit stays manual without new metadata.
        data.categories[1].automaticBudget = false
        add(90_000, month: 9, to: &data)
        add(40_000, month: 9, category: 1, to: &data)
        XCTAssertEqual(plan(data).limits[data.categories[0].id], 12_345)
        XCTAssertEqual(plan(data).limits[data.categories[1].id], 0)
        data.categories[0].automaticBudget = true
        XCTAssertEqual(plan(data).limits[data.categories[0].id], 90_000)
    }
    func testHistoricalAndFutureSelectionsCannotUseFutureEvidence() {
        var data = ledger()
        for (month, amount) in [(6, 6_000), (7, 7_000), (8, 8_000), (9, 90_000), (10, 999_999)] {
            add(amount, month: month, to: &data)
        }
        XCTAssertEqual(plan(data, month: 9).limits[data.categories[0].id], 7_000)
        XCTAssertEqual(plan(data, month: 12), plan(data, month: 10))
    }
    func testCentRoundingHistoryEditsAndModeRoundTrip() throws {
        var data = ledger()
        add(100, month: 8, to: &data); add(101, month: 9, to: &data)
        XCTAssertEqual(plan(data).limits[data.categories[0].id], 101)
        data.transactions[0].amount = 201
        XCTAssertEqual(plan(data).limits[data.categories[0].id], 151)
        data.categories[0].automaticBudget = true
        data.categories[1].automaticBudget = false
        let restored = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored, data)
        XCTAssertEqual(plan(restored), plan(data))
        // Older backups decode with the same manual-positive / automatic-unset default.
        let legacy = Data("{\"name\":\"Legacy\",\"symbol\":\"basket\",\"limit\":1234,\"id\":\"00000000-0000-0000-0000-000000000001\"}".utf8)
        XCTAssertFalse(try JSONDecoder().decode(Category.self, from: legacy).usesAutomaticBudget)
    }
    func testMergingAutomaticHistoryAndManualOverride() throws {
        var data = ledger()
        add(10_000, month: 9, to: &data); add(20_000, month: 9, category: 1, to: &data)
        let target = data.categories[1].id
        try data.mergeCategory(data.categories[0].id, into: target)
        XCTAssertEqual(plan(data).limits[target], 30_000)
        XCTAssertTrue(data.categories[0].usesAutomaticBudget)
        var manual = ledger()
        manual.categories[1].automaticBudget = false
        try manual.mergeCategory(manual.categories[0].id, into: manual.categories[1].id)
        XCTAssertFalse(manual.categories[0].usesAutomaticBudget)
    }
}
