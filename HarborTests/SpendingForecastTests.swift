import XCTest
@testable import HarborCore

// Fixed dates and isolated ledgers make time boundaries and financial predictions reproducible.
final class SpendingForecastTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ month: Int, _ day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }
    private func ledger() -> FinanceData {
        var data = FinanceData(isDemo: false)
        data.accounts = [Account(name: "Test", openingBalance: 0)]
        data.categories = [Category(name: "Housing", symbol: "house", limit: 0), Category(name: "Food", symbol: "basket", limit: 0)]
        for month in 4...9 {
            data.transactions += [
                Transaction(merchant: "Rent", amount: 150_000, kind: .expense, date: date(month), accountID: data.accounts[0].id, categoryID: data.categories[0].id),
                Transaction(merchant: "Food", amount: 10_000, kind: .expense, date: date(month, 20), accountID: data.accounts[0].id, categoryID: data.categories[1].id)
            ]
        }
        return data
    }
    private func forecast(_ data: FinanceData, month: Int = 10, day: Int = 15) -> SpendingForecast {
        SpendingForecast.calculate(data: data, month: date(month), now: date(10, day), calendar: calendar)
    }
    func testHistoryOnlyForecastAndNoLedgerMutation() {
        let data = ledger(), before = data
        let result = forecast(data)
        XCTAssertEqual(result.estimate, 160_000)
        XCTAssertEqual(result.actual, 0)
        XCTAssertNil(result.observedThrough)
        XCTAssertEqual(result.historyMonths, 6)
        XCTAssertEqual(result.backtestMonths, 4)
        XCTAssertEqual(result.meanAbsoluteError, 0)
        XCTAssertEqual(result.baselineError, 0)
        XCTAssertEqual(result.curve.last, result.estimate)
        XCTAssertEqual(data, before)
        XCTAssertTrue(result.warnings.contains { $0.contains("history only") })
    }
    func testRentAlreadyPaidIsNotExtrapolatedOrCountedTwice() {
        var data = ledger()
        data.transactions.append(Transaction(merchant: "Rent", amount: 155_000, kind: .expense, date: date(10), accountID: data.accounts[0].id, categoryID: data.categories[0].id))
        // Reminders must not double count expenses already represented in the historical profile.
        data.bills = [Bill(name: "Rent", amount: 155_000, due: date(10, 20), accountID: data.accounts[0].id, categoryID: data.categories[0].id)]
        let result = forecast(data)
        XCTAssertEqual(result.actual, 155_000)
        XCTAssertEqual(result.estimate, 165_000)
        XCTAssertEqual(result.categories.reduce(0) { $0 + $1.total }, result.estimate)
        XCTAssertEqual(result.curve.last, result.estimate)
        XCTAssertGreaterThanOrEqual(result.lower!, result.actual)
        XCTAssertEqual(result.observedThrough, date(10))
    }
    func testFutureTransactionsAndIncomeCannotLeakIntoPrediction() {
        var data = ledger()
        let before = forecast(data)
        data.transactions.append(Transaction(merchant: "Future", amount: 999_999, kind: .expense, date: date(10, 25), accountID: data.accounts[0].id, categoryID: data.categories[0].id))
        data.transactions.append(Transaction(merchant: "Pay", amount: 999_999, kind: .income, date: date(9, 30), accountID: data.accounts[0].id, categoryID: data.categories[0].id))
        let result = forecast(data)
        XCTAssertEqual(result.estimate, before.estimate)
        XCTAssertEqual(result.meanAbsoluteError, before.meanAbsoluteError)
        XCTAssertEqual(result.actual, 0)
    }
    func testHistoricalMonthsShowActualAndFutureMonthsUseHistory() {
        XCTAssertEqual(forecast(ledger(), month: 9).estimate, 160_000)
        XCTAssertTrue(forecast(ledger(), month: 9).isHistorical)
        let result = forecast(ledger(), month: 11)
        XCTAssertEqual(result.estimate, 160_000)
        XCTAssertFalse(result.isHistorical)
        XCTAssertTrue(result.warnings.contains { $0.contains("Recent history is missing") })
    }
    func testFutureMonthNeverTrainsOnIncompleteCurrentMonth() {
        var data = ledger()
        data.transactions.append(Transaction(merchant: "Large current purchase", amount: 900_000, kind: .expense, date: date(10, 5), accountID: data.accounts[0].id, categoryID: data.categories[1].id))
        let result = forecast(data, month: 11)
        XCTAssertEqual(result.estimate, 160_000)
        XCTAssertEqual(result.historyMonths, 6)
        XCTAssertEqual(result.meanAbsoluteError, 0)
    }
    func testSparseAndTruncatedHistoryDoNotCreateFalseForecast() {
        var data = ledger()
        data.transactions.removeAll { $0.date < date(9) }
        XCTAssertNil(forecast(data).estimate)
        data.transactions.removeAll { $0.date == date(9) }
        XCTAssertEqual(forecast(data).historyMonths, 0)
        XCTAssertNil(forecast(FinanceData(isDemo: false)).estimate)
    }
    func testMonthEndClampsPaymentDaysAndCurveIsMonotonic() {
        var data = ledger()
        for index in data.transactions.indices where data.transactions[index].merchant == "Food" {
            let month = calendar.component(.month, from: data.transactions[index].date)
            let last = calendar.range(of: .day, in: .month, for: date(month))!.count
            data.transactions[index].date = date(month, last)
        }
        let result = forecast(data, month: 11)
        XCTAssertEqual(result.curve.count, 30)
        XCTAssertEqual(result.curve.last, result.estimate)
        XCTAssertTrue(zip(result.curve, result.curve.dropFirst()).allSatisfy { $0 <= $1 })
    }
    func testOctoberExamplesAppendAndUpdateForecastWithoutReplacingHistory() throws {
        let historyURL = try XCTUnwrap(Bundle.module.url(forResource: "Transactions", withExtension: "csv", subdirectory: "Fixtures"))
        let examplesURL = try XCTUnwrap(Bundle.module.url(forResource: "OctoberExamples", withExtension: "csv", subdirectory: "Fixtures"))
        let history = try TransactionImport.csv(Data(contentsOf: historyURL))
        let examples = try TransactionImport.csv(Data(contentsOf: examplesURL))
        var data = FinanceData(isDemo: false)
        let account = Account(name: "Imported chequing", openingBalance: history.openingBalance!)
        try TransactionImport.apply(history.rows, to: &data, accountID: nil, newAccount: account, removeDemo: false)
        let previousHistory = data.transactions
        try TransactionImport.apply(examples.rows, to: &data, accountID: account.id, newAccount: nil, removeDemo: false)
        XCTAssertEqual(data.transactions.count, 423)
        XCTAssertTrue(previousHistory.allSatisfy { data.transactions.contains($0) })
        XCTAssertEqual(examples.rows.count, 16)
        XCTAssertTrue(examples.rows.allSatisfy { $0.note.hasPrefix("Fictional October example:") })
        XCTAssertEqual(examples.rows.filter { $0.kind == .income }.count, 2)
        XCTAssertEqual(TransactionImport.duplicates(examples.rows, in: data, account: account.id).count, 16)
        let result = forecast(data)
        XCTAssertEqual(result.actual, examples.expenses)
        XCTAssertEqual(data.total(.income, in: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15))!), examples.income)
        XCTAssertEqual(result.observedThrough, examples.rows.map(\.date).max())
        XCTAssertEqual(result.historyMonths, 6)
        XCTAssertEqual(result.curve.last, result.estimate)
        XCTAssertGreaterThan(result.estimate!, result.actual)
        print("OCTOBER WITH EXAMPLES: actual=\(result.actual), estimate=\(result.estimate!), income=\(examples.income), range=\(result.lower!)...\(result.upper!)")
    }
    func testSuppliedOctoberForecastAndRollingValidation() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Transactions", withExtension: "csv", subdirectory: "Fixtures"))
        let batch = try TransactionImport.csv(Data(contentsOf: url))
        var data = FinanceData(isDemo: false)
        try TransactionImport.apply(batch.rows, to: &data, accountID: nil, newAccount: Account(name: "Fixture", openingBalance: batch.openingBalance!), removeDemo: false)
        let result = forecast(data)
        XCTAssertEqual(result.historyMonths, 6)
        XCTAssertEqual(result.backtestMonths, 4)
        XCTAssertEqual(result.actual, 0)
        XCTAssertEqual(result.estimate, 392_196)
        XCTAssertEqual(result.meanAbsoluteError, 14_471)
        XCTAssertEqual(result.baselineError, 17_107)
        XCTAssertEqual(result.categories.reduce(0) { $0 + $1.total }, result.estimate)
        XCTAssertEqual(result.curve.last, result.estimate)
        XCTAssertLessThan(result.lower!, result.estimate!)
        XCTAssertGreaterThan(result.upper!, result.estimate!)
        print("OCTOBER FIXTURE: estimate=\(result.estimate!), range=\(result.lower!)...\(result.upper!), MAE=\(result.meanAbsoluteError!), baseline=\(result.baselineError!), recent=\(result.usesRecentWeights)")
    }
}
