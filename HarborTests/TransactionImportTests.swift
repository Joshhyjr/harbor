import XCTest
import PDFKit
import CoreText
@testable import HarborCore

// The supplied fictional documents are test-only resources, never bundled into the shipping app.
final class TransactionImportTests: XCTestCase {
    private func fixture(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")))
    }
    func testSuppliedCSVAndPDFMatchEveryTransaction() throws {
        let csv = try TransactionImport.csv(fixture("Transactions", "csv"))
        let pdf = try StatementPDFImport.parse(fixture("Statement", "pdf"))
        for batch in [csv, pdf] {
            XCTAssertEqual(batch.rows.count, 407)
            XCTAssertEqual(batch.income, 2_787_184)
            XCTAssertEqual(batch.expenses, 2_322_531)
            XCTAssertEqual(batch.openingBalance, 284_655)
            XCTAssertEqual(batch.closingBalance, 749_308)
        }
        for (a, b) in zip(csv.rows, pdf.rows) {
            XCTAssertEqual(a.date, b.date); XCTAssertEqual(a.merchant, b.merchant)
            XCTAssertEqual(a.amount, b.amount); XCTAssertEqual(a.kind, b.kind)
            XCTAssertEqual(a.category, b.category); XCTAssertEqual(a.balance, b.balance)
        }
        var data = FinanceData(isDemo: false)
        let account = Account(name: "Statement", openingBalance: csv.openingBalance!)
        try TransactionImport.apply(csv.rows, to: &data, accountID: nil, newAccount: account, removeDemo: false)
        XCTAssertEqual(data.balance(account.id), 749_308)
        XCTAssertEqual(data.categories.count, 19)
        XCTAssertEqual(data.budget, 0)
        // Clear statement labels no longer flood the inbox; ambiguous rows still need attention.
        XCTAssertTrue(data.transactions.contains { !$0.needsReview })
        XCTAssertTrue(data.transactions.contains( where: \.needsReview))
        // Named subscriptions are both correctly categorised and tracked without a confirmation queue.
        let cloud = try XCTUnwrap(data.bills.first { $0.name == "Apple iCloud" })
        XCTAssertEqual(data.category(cloud.categoryID)?.name, "Subscription")
        XCTAssertEqual(cloud.needsScheduleReview, false)
        XCTAssertFalse(data.transactions.filter { SubscriptionServices.name($0.merchant) == "Apple iCloud" }.contains(where: \.needsReview))
        XCTAssertEqual(TransactionImport.duplicates(pdf.rows, in: data, account: account.id).count, 407)
        XCTAssertTrue(TransactionImport.duplicates(pdf.rows, in: data, account: UUID()).isEmpty)
        // PDF and CSV must produce the same recurring evidence after validated extraction.
        let csvSuggestions = RecurringBills.suggestions(in: data)
        XCTAssertTrue(csvSuggestions.contains { $0.latest.merchant == "NOVA SCOTIA POWER" && $0.frequency == .monthly })
        var pdfData = FinanceData(isDemo: false)
        try TransactionImport.apply(pdf.rows, to: &pdfData, accountID: nil, newAccount: account, removeDemo: false)
        XCTAssertEqual(csvSuggestions.map(\.id), RecurringBills.suggestions(in: pdfData).map(\.id))
        XCTAssertEqual(csvSuggestions.map(\.minimum), RecurringBills.suggestions(in: pdfData).map(\.minimum))
        XCTAssertEqual(csvSuggestions.map(\.maximum), RecurringBills.suggestions(in: pdfData).map(\.maximum))
    }
    // User-supplied fictional formats reconcile independently and must agree on every financial field.
    func testExpandedCSVAndPDFMatchEveryTransaction() throws {
        let csv = try TransactionImport.csv(fixture("ExpandedTransactions", "csv"))
        let pdf = try StatementPDFImport.parse(fixture("ExpandedStatement", "pdf"))
        for batch in [csv, pdf] {
            XCTAssertEqual(batch.rows.count, 683)
            XCTAssertEqual(batch.openingBalance, 385025); XCTAssertEqual(batch.closingBalance, 476047)
            XCTAssertEqual(batch.income, 5320391); XCTAssertEqual(batch.expenses, 5229369)
            XCTAssertTrue(batch.hasPossibleTransfers)
        }
        for (a, b) in zip(csv.rows, pdf.rows) {
            XCTAssertEqual(a.date, b.date); XCTAssertEqual(a.merchant, b.merchant)
            XCTAssertEqual(a.amount, b.amount); XCTAssertEqual(a.kind, b.kind)
            XCTAssertEqual(a.category, b.category); XCTAssertEqual(a.balance, b.balance)
            XCTAssertFalse(b.note.isEmpty)
            XCTAssertTrue(a.note.hasSuffix(b.note), "Payment method mismatch at \(a.merchant)")
        }
        var data = FinanceData(isDemo: false)
        let account = Account(name: "Expanded sample", openingBalance: csv.openingBalance!)
        try TransactionImport.apply(csv.rows, to: &data, accountID: nil, newAccount: account, removeDemo: false)
        XCTAssertEqual(data.balance(account.id), 476047)
        XCTAssertEqual(TransactionImport.duplicates(pdf.rows, in: data, account: account.id).count, 683)
    }
    func testExpandedPDFRejectsMissingContinuationAndFinalPages() throws {
        // A plausible-looking partial table must not pass its published monthly/statement counts.
        let bytes = try fixture("ExpandedStatement", "pdf")
        for removed in [2, 29] {
            let document = try XCTUnwrap(PDFDocument(data: bytes))
            document.removePage(at: removed)
            XCTAssertThrowsError(try StatementPDFImport.parse(try XCTUnwrap(document.dataRepresentation())))
        }
    }
    func testCurrencySuffixAliasesRemainUnambiguous() throws {
        let text = "Date,Description,Money In (CAD),Money Out (CAD),Running Balance (CAD)\n2026-01-01,Salary,10.00,0,110.00\n2026-01-02,Shop,0,3.00,107.00"
        let batch = try TransactionImport.csv(Data(text.utf8))
        XCTAssertEqual(batch.openingBalance, 10000); XCTAssertEqual(batch.closingBalance, 10700)
        XCTAssertThrowsError(try TransactionImport.csv(Data("Date,Description,Amount,Amount (CAD)\n2026-01-01,Shop,-1,-1".utf8)))
    }
    func testScannedWatermarkedStatementRejectsUnreadableFinancialCells() throws {
        // Rasterize the supplied April pages so the fallback sees images, with no hidden PDF text.
        let source = try XCTUnwrap(PDFDocument(data: fixture("Statement", "pdf")))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let output = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        for index in 1...3 {
            let page = try XCTUnwrap(source.page(at: index))
            let context = try XCTUnwrap(CGContext(data: nil, width: 1530, height: 1980, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1530, height: 1980))
            context.scaleBy(x: 2.5, y: 2.5); page.draw(with: .mediaBox, to: context)
            output.beginPDFPage(nil); output.draw(try XCTUnwrap(context.makeImage()), in: mediaBox); output.endPDFPage()
        }
        output.closePDF()
        XCTAssertThrowsError(try StatementPDFImport.parse(Data(contentsOf: url))) { error in
            XCTAssertTrue(error.localizedDescription.contains("incomplete or ambiguous"))
        }
    }
    func testCleanScannedStatementUsesOCRAndReconciles() throws {
        // A clean image-only table exercises successful OCR; a watermarked scan above must fail safely.
        let context = try XCTUnwrap(CGContext(data: nil, width: 1530, height: 1980, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1530, height: 1980))
        context.scaleBy(x: 2.5, y: 2.5)
        func text(_ value: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 9) {
            let attrs: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil), .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attrs)), context)
        }
        text("APRIL 2026 CAD", 49, 700, size: 16)
        text("OPENING BALANCE", 49, 650, size: 7); text("$20.00", 49, 625, size: 13)
        text("DATE", 49, 580, size: 7); text("DESCRIPTION / CATEGORY", 101, 580, size: 7)
        text("MONEY OUT", 369, 580, size: 7); text("MONEY IN", 450, 580, size: 7); text("BALANCE", 520, 580, size: 7)
        text("04-01", 49, 550); text("COFFEE SHOP", 101, 550); text("$10.00", 380, 550); text("$10.00", 520, 550)
        text("Dining · CARD", 101, 540, size: 6.5)
        text("04-02", 49, 520); text("PAYROLL", 101, 520); text("$100.00", 450, 520); text("$110.00", 520, 520)
        text("Income · DIRECT DEP", 101, 510, size: 6.5)
        text("2/2 entries shown", 49, 470, size: 8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let output = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        output.beginPDFPage(nil); output.draw(try XCTUnwrap(context.makeImage()), in: box); output.endPDFPage(); output.closePDF()
        let batch = try StatementPDFImport.parse(Data(contentsOf: url))
        XCTAssertTrue(batch.usedOCR); XCTAssertEqual(batch.rows.count, 2)
        XCTAssertEqual(batch.openingBalance, 2000); XCTAssertEqual(batch.closingBalance, 11000)
        XCTAssertEqual(batch.expenses, 1000); XCTAssertEqual(batch.income, 10000)
    }

    func testCSVQuotingBOMAndSignedAmounts() throws {
        let text = "\u{feff}Date,Description,Amount,Note\r\n2026-04-01,\"Shop, \"\"One\"\"\",-12.34,\"line one\nline two\"\r\n2026-04-02,Payroll,1200.00,\r\n"
        let batch = try TransactionImport.csv(Data(text.utf8))
        XCTAssertEqual(batch.rows.count, 2)
        XCTAssertEqual(batch.rows[0].merchant, "Shop, \"One\"")
        XCTAssertEqual(batch.rows[0].note, "line one\nline two")
        XCTAssertEqual(batch.expenses, 1234)
        XCTAssertEqual(batch.income, 120000)
        XCTAssertNil(batch.openingBalance)
    }
    func testInvalidCSVsAreRejectedWithoutPartialImports() {
        for text in [
            "Date,Description,Amount\n2026-02-30,Shop,-1.00",
            "Date,Description,Amount\n2026-04-01,Shop,-1.001",
            "Date,Description,Amount\n2026-04-01,\"Shop,-1.00",
            "Date,Description,Amount\n2026-04-01,Shop,-1.00,extra",
            "Date,Description,Amount,Currency\n2026-04-01,Shop,-1.00,JPY",
            "Date,Description,Debit,Credit\n2026-04-01,Shop,1,2",
            "Date,Description,Amount,Balance\n2026-04-01,Shop,-1.00,9.00\n2026-04-02,Shop,-1.00,7.00",
            "Date,Description,Amount\n2026-04-02,Shop,-1\n2026-04-01,Shop,-1",
            "Date,Date,Description,Amount\n2026-04-01,2026-04-01,Shop,-1"
        ] { XCTAssertThrowsError(try TransactionImport.csv(Data(text.utf8)), text) }
    }
    func testFieldColumnAndRowLimitsRejectBoundaryOverflow() {
        // Include an unterminated final line so EOF cannot bypass the per-field/column caps.
        XCTAssertThrowsError(try CSVReader.read(String(repeating: "x", count: 10_001)))
        XCTAssertThrowsError(try CSVReader.read(Array(repeating: "x", count: 101).joined(separator: ",")))
        let text = "Date,Description,Amount\n" + String(repeating: "2026-04-01,Shop,-1\n", count: 10_001)
        XCTAssertThrowsError(try TransactionImport.csv(Data(text.utf8)))
    }
    func testDuplicateMatchingPreservesRepeatedPurchases() throws {
        let rows = try TransactionImport.csv(Data("Date,Description,Amount\n2026-04-01,Coffee,-5\n2026-04-01,Coffee,-5".utf8)).rows
        var data = FinanceData(isDemo: false)
        let account = Account(name: "Test", openingBalance: 10000)
        try TransactionImport.apply([rows[0]], to: &data, accountID: nil, newAccount: account, removeDemo: false)
        XCTAssertEqual(TransactionImport.duplicates(rows, in: data, account: account.id).count, 1)
        try TransactionImport.apply([rows[1]], to: &data, accountID: account.id, newAccount: nil, removeDemo: false)
        XCTAssertEqual(TransactionImport.duplicates(rows, in: data, account: account.id).count, 2)
    }
    // A repeated statement must not silently duplicate an opening balance through a new account.
    func testRepeatStatementSelectsExistingAccountAndGuardsNewAccount() throws {
        let csv = try TransactionImport.csv(fixture("Transactions", "csv"))
        let pdf = try StatementPDFImport.parse(fixture("Statement", "pdf"))
        var data = FinanceData(isDemo: false)
        let original = Account(name: "Original", openingBalance: csv.openingBalance!)
        try TransactionImport.apply(csv.rows, to: &data, accountID: nil, newAccount: original, removeDemo: false)
        XCTAssertEqual(TransactionImport.suggestedAccount(pdf.rows, in: data), original.id)
        let before = data
        let duplicate = Account(name: "Another", openingBalance: csv.openingBalance!)
        XCTAssertThrowsError(try TransactionImport.apply(pdf.rows, to: &data, accountID: nil, newAccount: duplicate, removeDemo: false))
        XCTAssertEqual(data, before)
        // Distinct accounts may legitimately share transactions, but require an explicit override.
        try TransactionImport.apply(pdf.rows, to: &data, accountID: nil, newAccount: duplicate, removeDemo: false, allowMatchingNewAccount: true)
        XCTAssertNil(TransactionImport.suggestedAccount(pdf.rows, in: data))
        XCTAssertEqual(TransactionImport.matchingAccounts(pdf.rows, in: data).count, 2)
        XCTAssertEqual(data.balance(original.id), csv.closingBalance)
        XCTAssertEqual(data.balance(duplicate.id), csv.closingBalance)
    }
    func testPartialOverlapWarnsWithoutChoosingAnAccount() throws {
        let rows = try TransactionImport.csv(Data("Date,Description,Amount\n2026-04-01,Shop,-1\n2026-04-02,Shop,-2\n2026-04-03,Shop,-3".utf8)).rows
        var data = FinanceData(isDemo: false)
        let account = Account(name: "Test", openingBalance: 10000)
        try TransactionImport.apply([rows[0]], to: &data, accountID: nil, newAccount: account, removeDemo: false)
        XCTAssertEqual(TransactionImport.matchingAccounts(rows, in: data).first?.count, 1)
        XCTAssertNil(TransactionImport.suggestedAccount(rows, in: data))
        XCTAssertNil(TransactionImport.suggestedAccount([rows[0]], in: data))
        XCTAssertTrue(TransactionImport.matchingAccounts([rows[1]], in: data).isEmpty)
    }
    func testFailedApplyIsAtomicAndDemoRemovalIsExplicit() throws {
        let rows = try TransactionImport.csv(Data("Date,Description,Amount\n2026-04-01,Shop,-50000".utf8)).rows
        var data = FinanceData.demo()
        let before = data
        XCTAssertThrowsError(try TransactionImport.apply(rows, to: &data, accountID: data.accounts[1].id, newAccount: nil, removeDemo: false))
        XCTAssertEqual(data, before)
        let account = Account(name: "Real account", openingBalance: 6000000)
        try TransactionImport.apply(rows, to: &data, accountID: nil, newAccount: account, removeDemo: true)
        XCTAssertEqual(data.accounts.count, 1); XCTAssertEqual(data.transactions.count, 1)
        XCTAssertTrue(data.goals.isEmpty); XCTAssertTrue(data.bills.isEmpty); XCTAssertFalse(data.isDemo)
    }
}
