import XCTest
@testable import HarborCore

// Use real CSV parsing and integer arithmetic, with independent expected balances and row counts.
final class StatementHistoryTests: XCTestCase {
    private func batch() throws -> ImportBatch {
        try TransactionImport.csv(Data("Date,Description,Money In (CAD),Money Out (CAD),Balance (CAD)\n2026-09-01,Payroll,100.00,,1100.00\n2026-09-15,Groceries,,20.00,1080.00\n2026-09-30,Cafe,,5.00,1075.00\n".utf8))
    }
    private func imported() throws -> (FinanceData, Account, ImportBatch) {
        let source = try batch()
        var data = FinanceData(isDemo: false)
        let account = Account(name: "Chequing", openingBalance: 100_000)
        try TransactionImport.applyWithHistory(source.rows, batch: source, filename: "/private/source/September.csv", to: &data,
            accountID: nil, newAccount: account, removeDemo: false, currencyCode: "CAD")
        return (data, account, source)
    }
    private func check(_ account: Account, balance: Int = 107_500, day: String = "2026-09-30") -> StatementBalanceCheck {
        StatementBalanceCheck(accountID: account.id, accountName: account.name, currency: account.currency, closingDay: day, statementBalance: balance)
    }
    func testCSVReceiptAndDuplicateOnlyImportDoNotChangeFinancialRecords() throws {
        var (data, account, source) = try imported()
        let receipt = try XCTUnwrap(data.statementImports?.first)
        XCTAssertEqual(data.version, 3)
        XCTAssertEqual(receipt.filename, "September.csv")
        XCTAssertEqual(receipt.totalRows, 3); XCTAssertEqual(receipt.addedRows, 3)
        XCTAssertEqual(receipt.matchedRows, 0); XCTAssertEqual(receipt.duplicatesSkipped, 0)
        XCTAssertEqual(receipt.openingBalance, 100_000); XCTAssertEqual(receipt.closingBalance, 107_500)
        XCTAssertEqual(Set(receipt.addedTransactionIDs), Set(data.transactions.map(\.id)))
        let transactions = data.transactions, accounts = data.accounts, categories = data.categories
        try TransactionImport.applyWithHistory([], batch: source, filename: "Repeated.pdf", to: &data,
            accountID: account.id, newAccount: nil, removeDemo: false, currencyCode: "CAD")
        let skipped = try XCTUnwrap(data.statementImports?.last)
        XCTAssertEqual(skipped.addedRows, 0); XCTAssertEqual(skipped.duplicatesSkipped, 3)
        XCTAssertEqual(skipped.deselectedRows, 0); XCTAssertEqual(skipped.addedTransactionIDs, [])
        XCTAssertEqual(data.transactions, transactions); XCTAssertEqual(data.accounts, accounts); XCTAssertEqual(data.categories, categories)
        XCTAssertEqual(data.balance(account.id), 107_500)
    }
    func testPartialImportSeparatesDuplicatesAndUncheckedRows() throws {
        var (data, account, source) = try imported()
        data.transactions.removeLast(2)
        try TransactionImport.applyWithHistory([source.rows[1]], batch: source, filename: "Partial.csv", to: &data,
            accountID: account.id, newAccount: nil, removeDemo: false, currencyCode: "CAD")
        let receipt = try XCTUnwrap(data.statementImports?.last)
        XCTAssertEqual(receipt.addedRows, 1); XCTAssertEqual(receipt.duplicatesSkipped, 1); XCTAssertEqual(receipt.deselectedRows, 1)
        XCTAssertEqual(receipt.totalRows, 3)
        XCTAssertEqual(data.balance(account.id), 108_000)
    }
    func testInvalidImportOrReceiptIsAtomic() throws {
        var (data, account, source) = try imported()
        let before = data
        XCTAssertThrowsError(try TransactionImport.applyWithHistory(source.rows, batch: source, filename: String(repeating: "x", count: 1001), to: &data,
            accountID: account.id, newAccount: nil, removeDemo: false, currencyCode: "CAD"))
        XCTAssertEqual(data, before)
        var invalid = source.rows[0]; invalid.amount = 0
        XCTAssertThrowsError(try TransactionImport.applyWithHistory([invalid], batch: source, filename: "Invalid.csv", to: &data,
            accountID: account.id, newAccount: nil, removeDemo: false, currencyCode: "CAD"))
        XCTAssertEqual(data, before)
        var foreign = source; foreign.currencyCode = "USD"
        XCTAssertThrowsError(try TransactionImport.applyWithHistory([], batch: foreign, filename: "Wrong-currency.csv", to: &data,
            accountID: account.id, newAccount: nil, removeDemo: false, currencyCode: "CAD"))
        XCTAssertEqual(data, before)
    }
    func testCaptureConfirmationReceiptDoesNotCountAsNewSpending() throws {
        var data = FinanceData(isDemo: false)
        let account = Account(name: "Card", openingBalance: 10_000)
        data.accounts = [account]
        let tap = try ApplePayCapture(amount: "5", merchant: "Cafe", date: XCTUnwrap(TransactionImport.date("2026-09-30")), currency: "CAD", accountID: account.id)
        try tap.apply(to: &data)
        var row = try XCTUnwrap(batch().rows.last); row.reconcileTransactionID = tap.id
        let source = ImportBatch(rows: [row], currencyCode: "CAD")
        try TransactionImport.applyWithHistory([row], batch: source, filename: "Card.csv", to: &data,
            accountID: account.id, newAccount: nil, removeDemo: false, currencyCode: "CAD")
        XCTAssertEqual(data.statementImports?.last?.addedRows, 0)
        XCTAssertEqual(data.statementImports?.last?.matchedRows, 1)
        XCTAssertEqual(data.statementImports?.last?.matchedTransactionIDs, [tap.id])
        XCTAssertEqual(data.transactions.count, 1); XCTAssertEqual(data.balance(account.id), 9_500)
    }
    func testTransferReceiptCountsSourceRowsSeparatelyFromLinkedEntries() throws {
        var data = FinanceData(isDemo: false)
        let account = Account(name: "Chequing", openingBalance: 100_000)
        data.accounts = [account]
        let row = ImportRow(date: try XCTUnwrap(TransactionImport.date("2026-09-20")), merchant: "Transfer to savings", amount: 10_000, kind: .expense, category: "Transfer", note: "", balance: nil)
        let source = ImportBatch(rows: [row], currencyCode: "CAD")
        try TransactionImport.applyWithHistory([row], batch: source, filename: "Savings.csv", to: &data,
            accountID: account.id, newAccount: nil, removeDemo: false, currencyCode: "CAD", autoSavings: true)
        XCTAssertEqual(data.statementImports?.last?.addedRows, 1)
        XCTAssertEqual(data.statementImports?.last?.addedTransactionIDs.count, 2)
        XCTAssertEqual(try StatementReconciliation.calculate(check(account, balance: 90_000), in: data).difference, 0)
        XCTAssertEqual(data.netWorth, 100_000)
    }
    func testClosingDayIncludesLatePurchasesButExcludesFollowingDayAndOtherCurrencies() throws {
        var (data, account, _) = try imported()
        let category = try XCTUnwrap(data.categories.first)
        let closingDay = try XCTUnwrap(TransactionImport.date("2026-09-30"))
        let late = try XCTUnwrap(Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: closingDay))
        let nextDay = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: closingDay))
        data.transactions.append(Transaction(merchant: "Late purchase", amount: 100, kind: .expense, date: late, accountID: account.id, categoryID: category.id))
        data.transactions.append(Transaction(merchant: "Next month", amount: 5_000, kind: .expense, date: nextDay, accountID: account.id, categoryID: category.id))
        data.accounts.append(Account(name: "USD", openingBalance: 999_999, currencyCode: "USD"))
        let result = try StatementReconciliation.calculate(check(account, balance: 107_400), in: data)
        XCTAssertEqual(result.difference, 0); XCTAssertEqual(result.entries.count, 4)
        XCTAssertEqual(data.balance(account.id), 102_400)
    }
    func testSavedComparisonsRecalculateAfterEditsAndUpsertByClosingDay() throws {
        var (data, account, _) = try imported()
        try data.saveStatementCheck(check(account))
        let originalID = try XCTUnwrap(data.statementBalanceChecks?.first?.id)
        let saved = try XCTUnwrap(data.statementBalanceChecks?.first)
        data.transactions[0].amount += 250
        XCTAssertEqual(try StatementReconciliation.calculate(saved, in: data).difference, 250)
        try data.saveStatementCheck(check(account, balance: 107_750))
        XCTAssertEqual(data.statementBalanceChecks?.count, 1)
        XCTAssertEqual(data.statementBalanceChecks?.first?.id, originalID)
        XCTAssertEqual(try StatementReconciliation.calculate(XCTUnwrap(data.statementBalanceChecks?.first), in: data).difference, 0)
    }
    func testHistoryAndComparisonsSurvivePortableBackupAndTransactionDeletion() throws {
        var (data, account, _) = try imported()
        try data.saveStatementCheck(check(account))
        let receipt = data.statementImports
        data.transactions.removeAll()
        XCTAssertEqual(data.statementImports, receipt)
        let key = PortableBackup.recoveryKey()
        let recovered = try PortableBackup.decode(PortableBackup.encrypt(data, recoveryKey: key), recoveryKey: key)
        XCTAssertEqual(recovered, data)
        XCTAssertEqual(try StatementReconciliation.calculate(XCTUnwrap(recovered.statementBalanceChecks?.first), in: recovered).difference, -7_500)
        var downgraded = data; downgraded.version = 2
        XCTAssertThrowsError(try downgraded.validate())
        var old = FinanceData.demo(); old.version = 1
        let legacy = try PortableBackup.decode(JSONEncoder().encode(old))
        XCTAssertNil(legacy.statementImports); XCTAssertNil(legacy.statementBalanceChecks)
    }
    func testInvalidComparisonsAndHistoryFailWithoutChangingLedger() throws {
        var (data, account, _) = try imported()
        let before = data
        for bad in [check(account, balance: Int.min), check(account, day: "2026-02-30"), check(Account(name: "Missing", openingBalance: 0))] {
            XCTAssertThrowsError(try data.saveStatementCheck(bad))
            XCTAssertEqual(data, before)
        }
        var broken = data; broken.statementImports?[0].duplicatesSkipped = -1
        XCTAssertThrowsError(try broken.validate())
        broken = data; broken.statementImports?[0].totalRows += 1
        XCTAssertThrowsError(try broken.validate())
    }
    func testProvisionalCapturesRemainVisibleWhenBalancesHappenToMatch() throws {
        var (data, account, _) = try imported()
        let capture = try ApplePayCapture(amount: "1", merchant: "Unposted", date: XCTUnwrap(TransactionImport.date("2026-09-30")), currency: "CAD", accountID: account.id)
        try capture.apply(to: &data)
        let result = try StatementReconciliation.calculate(check(account, balance: 107_400), in: data)
        XCTAssertEqual(result.difference, 0); XCTAssertEqual(result.provisional.map(\.id), [capture.id])
    }
    // Reopening uses the most recently compared account, falling back when it is removed or incompatible.
    func testMostRecentComparisonSelectsOnlyAnAvailableAccountInItsRecordedCurrency() throws {
        var (data, account, _) = try imported()
        let other = Account(name: "USD savings", openingBalance: 0, currencyCode: "USD")
        data.accounts.append(other)
        var first = check(account); first.savedAt = Date(timeIntervalSince1970: 1_000)
        var second = check(other, balance: 0); second.savedAt = Date(timeIntervalSince1970: 2_000)
        try data.saveStatementCheck(first); try data.saveStatementCheck(second)
        XCTAssertEqual(data.mostRecentStatementAccountID, other.id)
        data.accounts[1].currencyCode = "EUR"
        XCTAssertEqual(data.mostRecentStatementAccountID, account.id)
        data.accounts.removeLast()
        XCTAssertEqual(data.mostRecentStatementAccountID, account.id)
    }
}
