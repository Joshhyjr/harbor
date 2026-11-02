import XCTest
import PDFKit
@testable import HarborCore

// These tests prove currency separation and balanced transfers rather than merely checking formatted labels.
final class CurrencyAndSavingsTests: XCTestCase {
    private func fixture(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")))
    }
    func testCurrencyEvidenceAndConflictRejection() throws {
        for code in ["USD", "GBP", "EUR", "CAD"] {
            let batch = try TransactionImport.csv(Data("Date,Description,Money In (\(code)),Money Out (\(code)),Running Balance (\(code))\n2026-01-01,Shop,0,12.50,87.50".utf8))
            XCTAssertEqual(batch.currencyCode, code); XCTAssertEqual(batch.openingBalance, 10000)
        }
        XCTAssertEqual(try Currency.detect("Balance £1,000.00"), "GBP")
        XCTAssertEqual(TransactionImport.cents("£1,000.00"), 100000)
        XCTAssertEqual(TransactionImport.cents("($12.50)"), -1250)
        XCTAssertEqual(TransactionImport.cents("-£12.50"), -1250)
        XCTAssertNil(TransactionImport.cents("(-£12.50)"))
        XCTAssertNil(try Currency.detect("Balance $100.00"))
        for text in ["USD GBP", "CAD £100", "JPY"] { XCTAssertThrowsError(try Currency.detect(text)) }
        XCTAssertThrowsError(try TransactionImport.csv(Data("Date,Description,Amount,Currency\n2026-01-01,Shop,-1,USD\n2026-01-02,Shop,-1,GBP".utf8)))
        XCTAssertThrowsError(try TransactionImport.csv(Data("Date,Description,Amount,Currency\n2026-01-01,Shop,-1,XYZ".utf8)))
        XCTAssertTrue(Money.format(10000, currency: "USD").contains("USD"))
        XCTAssertTrue(Money.format(10000, currency: "GBP").contains("GBP"))
    }
    func testReportingNeverAddsDifferentCurrenciesOrUsesWrongBudgets() throws {
        var data = FinanceData(isDemo: false)
        let cad = Account(name: "Canada", openingBalance: 10000), usd = Account(name: "US", openingBalance: 20000, currencyCode: "USD")
        data.accounts = [cad, usd]
        let cadCategory = Category(name: "Other", symbol: "tag", limit: 1000), usdCategory = Category(name: "Other", symbol: "tag", limit: 2000, currencyCode: "USD")
        data.categories = [cadCategory, usdCategory]
        let now = Date()
        data.transactions = [Transaction(merchant: "Shop", amount: 100, kind: .expense, date: now, accountID: cad.id, categoryID: cadCategory.id), Transaction(merchant: "Shop", amount: 200, kind: .expense, date: now, accountID: usd.id, categoryID: usdCategory.id)]
        try data.validate()
        XCTAssertEqual(data.netWorth, 9900); XCTAssertEqual(data.netWorth(in: "USD"), 19800)
        XCTAssertEqual(data.total(.expense, in: now), 100); XCTAssertEqual(data.budget, 1000)
        XCTAssertEqual(SpendingForecast.calculate(data: data, month: now).actual, 100)
        data.reportingCurrencyCode = "USD"
        XCTAssertEqual(data.netWorth, 19800); XCTAssertEqual(data.budget, 2000)
        XCTAssertEqual(data.total(.expense, in: now), 200)
        XCTAssertEqual(SpendingForecast.calculate(data: data, month: now).actual, 200)
    }
    func testForeignImportPreservesAccountUnitsAndRejectsMismatchAtomically() throws {
        let batch = try TransactionImport.csv(Data("Date,Description,Amount,Currency\n2026-01-01,Shop,-10,USD".utf8))
        var data = FinanceData(isDemo: false)
        let cad = Account(name: "CAD", openingBalance: 10000)
        data.accounts = [cad]
        let before = data
        XCTAssertThrowsError(try TransactionImport.apply(batch.rows, to: &data, accountID: cad.id, newAccount: nil, removeDemo: false, currencyCode: "USD"))
        XCTAssertEqual(data, before)
        let usd = Account(name: "USD", openingBalance: 10000, currencyCode: "USD")
        try TransactionImport.apply(batch.rows, to: &data, accountID: nil, newAccount: usd, removeDemo: false, currencyCode: "USD")
        XCTAssertEqual(data.balance(usd.id), 9000); XCTAssertEqual(data.balance(cad.id), 10000)
        XCTAssertEqual(data.categories.first?.currency, "USD")
        XCTAssertTrue(TransactionImport.duplicates(batch.rows, in: data, account: cad.id).isEmpty)
        XCTAssertEqual(TransactionImport.suggestedAccount(batch.rows + batch.rows + batch.rows, in: data), nil)
        try data.validate()
    }
    func testExpandedSavingsCreatesOneAccountAndPreservesSourceReconciliation() throws {
        let csv = try TransactionImport.csv(fixture("ExpandedTransactions", "csv"))
        let pdf = try StatementPDFImport.parse(fixture("ExpandedStatement", "pdf"))
        var data = FinanceData(isDemo: false)
        let account = Account(name: "Chequing", openingBalance: csv.openingBalance!)
        try TransactionImport.apply(csv.rows, to: &data, accountID: nil, newAccount: account, removeDemo: false, currencyCode: "CAD", autoSavings: true)
        XCTAssertEqual(data.accounts.count, 2)
        let savings = try XCTUnwrap(data.accounts.first { $0.savingsSourceAccountID == account.id })
        XCTAssertEqual(data.balance(account.id), 476047); XCTAssertEqual(data.balance(savings.id), 285000)
        XCTAssertEqual(data.netWorth, 761047)
        XCTAssertEqual(data.transactions.filter(\.isTransfer).count, 18)
        XCTAssertEqual(data.transactions.count, 692)
        XCTAssertEqual(data.transactions.filter { !$0.isTransfer && $0.kind == .expense }.reduce(0) { $0 + $1.amount }, 4944369)
        XCTAssertEqual(data.transactions.filter { !$0.isTransfer && $0.kind == .income }.reduce(0) { $0 + $1.amount }, 5320391)
        XCTAssertEqual(TransactionImport.duplicates(pdf.rows, in: data, account: account.id).count, 683)
        XCTAssertFalse(RecurringBills.suggestions(in: data).contains { $0.latest.merchant == "TRANSFER TO SAVINGS" })
        let before = data
        XCTAssertThrowsError(try TransactionImport.apply(csv.rows, to: &data, accountID: account.id, newAccount: nil, removeDemo: false, autoSavings: true))
        XCTAssertEqual(data, before)
        let reopened = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(reopened, data); try reopened.validate()
    }
    func testSavingsReuseDestinationDuplicatesAndPairedEdits() throws {
        let csv = try TransactionImport.csv(Data("Date,Description,Amount,Currency\n2026-01-01,TRANSFER TO SAVINGS,-25,USD\n2026-02-01,TRANSFER TO SAVINGS,-30,USD".utf8))
        var data = FinanceData(isDemo: false)
        let source = Account(name: "USD Chequing", openingBalance: 10000, currencyCode: "USD")
        try TransactionImport.apply([csv.rows[0]], to: &data, accountID: nil, newAccount: source, removeDemo: false, autoSavings: true)
        try TransactionImport.apply([csv.rows[1]], to: &data, accountID: source.id, newAccount: nil, removeDemo: false, autoSavings: true)
        XCTAssertEqual(data.accounts.count, 2)
        let savings = try XCTUnwrap(data.accounts.first { $0.savingsSourceAccountID == source.id })
        XCTAssertEqual(savings.currency, "USD"); XCTAssertEqual(data.balance(savings.id), 5500)
        XCTAssertEqual(data.netWorth, 10000)
        let laterStatement = try TransactionImport.csv(Data("Date,Description,Amount,Currency\n2026-01-01,TRANSFER CREDIT,25,USD\n2026-02-01,TRANSFER CREDIT,30,USD".utf8))
        XCTAssertEqual(TransactionImport.duplicates(laterStatement.rows, in: data, account: savings.id).count, 2)
        var entry = try XCTUnwrap(data.transactions.first { $0.accountID == source.id })
        entry.amount = 2600
        try data.replaceTransaction(entry); try data.validate()
        XCTAssertEqual(data.netWorth, 10000)
        data.deleteTransaction(entry.id); try data.validate()
        XCTAssertEqual(data.transactions.count, 2); XCTAssertEqual(data.netWorth, 10000)
        XCTAssertEqual(data.balance(savings.id), 3000)
    }
    func testExistingSavingsCreditIsLinkedWithoutDoubleCounting() throws {
        var data = FinanceData(isDemo: false)
        let source = Account(name: "Chequing", openingBalance: 10000), savings = Account(name: "Savings", openingBalance: 50000)
        let category = Category(name: "Transfers", symbol: "arrow.left.arrow.right", limit: 0)
        data.accounts = [source, savings]; data.categories = [category]
        let batch = try TransactionImport.csv(Data("Date,Description,Amount,Currency\n2026-01-01,TRANSFER TO SAVINGS,-25,CAD".utf8))
        data.transactions = [Transaction(merchant: "TRANSFER CREDIT", amount: 2500, kind: .income, date: batch.rows[0].date, accountID: savings.id, categoryID: category.id)]
        try TransactionImport.apply(batch.rows, to: &data, accountID: source.id, newAccount: nil, removeDemo: false, autoSavings: true, savingsAccountID: savings.id)
        XCTAssertEqual(data.accounts.count, 2); XCTAssertEqual(data.transactions.count, 2)
        XCTAssertTrue(data.transactions.allSatisfy(\.isTransfer)); try data.validate()
        XCTAssertEqual(data.balance(savings.id), 52500)
    }
    func testLegacyBackupDefaultsRemainCAD() throws {
        var legacy = FinanceData.demo()
        legacy.version = 1
        let restored = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(restored.reportingCurrency, "CAD")
        XCTAssertTrue(restored.accounts.allSatisfy { $0.currency == "CAD" })
        XCTAssertEqual(restored.netWorth, legacy.netWorth); try restored.validate()
    }
    func testExistingSavingsReviewPreservesSourceIDsAndCannotRepeat() throws {
        let csv = try TransactionImport.csv(fixture("ExpandedTransactions", "csv"))
        var data = FinanceData(isDemo: false)
        let source = Account(name: "Previously imported", openingBalance: csv.openingBalance!)
        try TransactionImport.apply(csv.rows, to: &data, accountID: nil, newAccount: source, removeDemo: false)
        let ids = data.transactions.map(\.id)
        let selection = Set(data.savingsCandidates.map(\.id))
        XCTAssertEqual(selection.count, 9)
        try data.trackExistingSavingsTransfers(selection)
        XCTAssertEqual(data.balance(source.id), 476047)
        XCTAssertEqual(Set(data.transactions.filter { $0.accountID == source.id }.map(\.id)), Set(ids))
        XCTAssertTrue(data.savingsCandidates.isEmpty)
        let before = data
        XCTAssertThrowsError(try data.trackExistingSavingsTransfers(selection)); XCTAssertEqual(data, before)
        try data.validate()
    }
    func testInvalidTransferPairAndCrossCurrencyTargetFailAtomically() throws {
        let batch = try TransactionImport.csv(fixture("USDSavings", "csv"))
        var data = FinanceData(isDemo: false)
        let cadSavings = Account(name: "CAD Savings", openingBalance: 10000)
        data.accounts = [cadSavings]
        let source = Account(name: "US", openingBalance: batch.openingBalance!, currencyCode: "USD")
        let before = data
        XCTAssertThrowsError(try TransactionImport.apply(batch.rows, to: &data, accountID: nil, newAccount: source, removeDemo: false, autoSavings: true, savingsAccountID: cadSavings.id))
        XCTAssertEqual(data, before)
        try TransactionImport.apply(batch.rows, to: &data, accountID: nil, newAccount: source, removeDemo: false, autoSavings: true)
        data.transactions.removeAll { $0.derivedTransfer == true }
        XCTAssertThrowsError(try data.validate())
    }
    func testAdaptiveTableMappingRejectsAmbiguousDatesAndBalances() throws {
        let table = [["Posting Date", "Payee", "Paid Out", "Paid In", "Balance"], ["2026-10-01", "Shop", "12.50", "-", "87.50"], ["2026-10-02", "Employer", "-", "20", "107.50"]]
        let batch = try DocumentTableImport.parse(table, context: "GBP", currency: "GBP")
        XCTAssertEqual(batch.currency, "GBP"); XCTAssertEqual(batch.rows.count, 2)
        var ambiguous = table; ambiguous[1][0] = "01/02/2026"
        XCTAssertThrowsError(try DocumentTableImport.parse(ambiguous, context: "GBP", currency: "GBP"))
        var badBalance = table; badBalance[2][4] = "999.00"
        XCTAssertThrowsError(try DocumentTableImport.parse(badBalance, context: "GBP", currency: "GBP"))
    }
    func testLiveVisionDocumentRecognitionOnUnfamiliarGBPTable() async throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { throw XCTSkip("Vision document recognition requires OS 26.") }
        let bytes = try fixture("VisionGBPStatement", "pdf")
        let batch = try await StatementPDFImport.parseWithDocumentRecognition(bytes)
        XCTAssertTrue(batch.usedDocumentRecognition); XCTAssertTrue(batch.usedOCR)
        XCTAssertEqual(batch.currency, "GBP"); XCTAssertEqual(batch.rows.count, 3)
        XCTAssertEqual(batch.openingBalance, 10000); XCTAssertEqual(batch.closingBalance, 10500)
        XCTAssertEqual(batch.income, 2000); XCTAssertEqual(batch.expenses, 1500)
    }
}
