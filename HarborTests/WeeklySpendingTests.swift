import XCTest
@testable import HarborCore

// Boundary and filtering checks protect the weekly drill-down from overstating spending.
final class WeeklySpendingTests: XCTestCase {
    func testWeeksPartitionMonthAndExcludeTransfersIncomeAndOtherCurrencies() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        func date(_ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))! }
        var data = FinanceData.demo()
        data.transactions = []
        let cad = Account(name: "CAD", openingBalance: 0, currencyCode: "CAD")
        let usd = Account(name: "USD", openingBalance: 0, currencyCode: "USD")
        data.accounts = [cad, usd]
        data.reportingCurrencyCode = "CAD"
        let category = data.categories[0].id
        func entry(_ day: Int, _ cents: Int, account: UUID? = nil, kind: TransactionKind = .expense) -> Transaction {
            Transaction(merchant: "Fixture", amount: cents, kind: kind, date: date(day), accountID: account ?? cad.id, categoryID: category)
        }
        data.transactions = [entry(1, 101), entry(4, 202), entry(5, 303), entry(31, 404), entry(0, 999), entry(32, 999), entry(3, 999, account: usd.id), entry(3, 999, kind: .income)]
        var transfer = entry(2, 999)
        transfer.transferPairID = UUID()
        transfer.transferAccountID = usd.id
        data.transactions.append(transfer)
        let weeks = SpendingWeek.calculate(data: data, month: date(15), calendar: calendar)
        XCTAssertEqual(weeks.count, 5)
        XCTAssertEqual(weeks.map { $0.days.count }, [4, 7, 7, 7, 6])
        XCTAssertEqual(weeks.flatMap(\.days).count, 31)
        XCTAssertEqual(Set(weeks.flatMap(\.days)).count, 31)
        XCTAssertEqual(weeks.map(\.total), [303, 303, 0, 0, 404])
        XCTAssertEqual(weeks.reduce(0) { $0 + $1.total }, data.total(.expense, in: date(15)))
        XCTAssertEqual(weeks[0].entries(on: date(1), calendar: calendar).map(\.amount), [101])
    }

    func testLeapMonthAcrossDaylightSavingProducesEveryDayOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Halifax")!
        let data = FinanceData.demo()
        for (year, month, expected) in [(2024, 2, 29), (2026, 3, 31), (2026, 11, 30)] {
            let date = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            let days = SpendingWeek.calculate(data: data, month: date, calendar: calendar).flatMap(\.days)
            XCTAssertEqual(days.count, expected)
            XCTAssertEqual(Set(days).count, expected)
        }
    }
}
