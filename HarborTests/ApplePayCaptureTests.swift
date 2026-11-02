import XCTest
import CryptoKit
@testable import HarborCore

final class ApplePayCaptureTests: XCTestCase {
    // Restore can remove an account; correcting it must preserve encrypted custody and the capture ID.
    func testHeldCaptureReassignmentPreservesQuarantineAndRejectsCurrencyChange() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let active = ApplePayInbox(folder: folder, key: SymmetricKey(size: .bits256))
        let capture = try ApplePayCapture(amount: "8.25", merchant: "Held shop", currency: "CAD", accountID: UUID())
        try active.save(capture)
        try ApplePayInbox.quarantineFiles(in: folder)
        let held = ApplePayInbox(folder: folder.appendingPathComponent("quarantine"), key: active.key)
        let file = try XCTUnwrap(held.files().first)
        let before = try Data(contentsOf: file)
        let wrongCurrency = Account(name: "USD", openingBalance: 0, currencyCode: "USD")
        XCTAssertThrowsError(try held.reassign(file, to: wrongCurrency))
        XCTAssertEqual(try Data(contentsOf: file), before)
        var data = FinanceData(isDemo: false)
        let destination = Account(name: "Restored account", openingBalance: 10_000)
        data.accounts = [destination]
        XCTAssertThrowsError(try active.reassign(file, to: destination))
        try held.reassign(file, to: destination)
        var expected = capture; expected.accountID = destination.id
        XCTAssertEqual(try held.read(file), expected)
        XCTAssertTrue(try active.files().isEmpty)
        XCTAssertEqual(try held.files().count, 1)
        // Explicit release and a fresh inbox instance model the next launch after restoration.
        let released = folder.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.moveItem(at: file, to: released)
        let reopened = ApplePayInbox(folder: folder, key: active.key)
        try reopened.read(released).apply(to: &data)
        XCTAssertEqual(data.transactions.count, 1)
        XCTAssertEqual(data.transactions.first?.id, capture.id)
        XCTAssertEqual(data.balance(destination.id), 9_175)
    }
    // A crash after encrypted ledger commit but before inbox deletion must not charge the account twice.
    func testRetryAfterEncryptedLedgerReloadPreservesBalance() throws {
        var data = FinanceData(isDemo: false)
        let account = Account(name: "Card", openingBalance: 10_000)
        data.accounts = [account]
        let capture = try ApplePayCapture(amount: "12.34", merchant: "Restart shop", currency: "CAD", accountID: account.id)
        try capture.apply(to: &data)
        let key = SymmetricKey(size: .bits256)
        let saved = try LedgerCipher.encrypt(JSONEncoder().encode(data), key: key)
        var reopened = try JSONDecoder().decode(FinanceData.self, from: LedgerCipher.decrypt(saved, key: key))
        try capture.apply(to: &reopened)
        XCTAssertEqual(reopened, data)
        XCTAssertEqual(reopened.balance(account.id), 8_766)
    }
    // Stable IDs prevent retries from duplicating a committed purchase, without collapsing genuine repeats.
    func testIdentityAndValidation() throws {
        var data = FinanceData.demo()
        let account = try XCTUnwrap(data.accounts.first)
        let capture = try ApplePayCapture(amount: "12.34", merchant: "Unknown shop", currency: account.currency, accountID: account.id)
        let count = data.transactions.count
        try capture.apply(to: &data)
        try capture.apply(to: &data)
        XCTAssertEqual(data.transactions.count, count + 1)
        XCTAssertEqual(data.transactions.last?.amount, 1234)
        XCTAssertEqual(data.transactions.last?.needsReview, true)
        let second = try ApplePayCapture(amount: "12.34", merchant: "Unknown shop", currency: account.currency, accountID: account.id)
        try second.apply(to: &data)
        XCTAssertEqual(data.transactions.count, count + 2)
        for amount in ["0", "-1", "1.001", "NaN", ""] {
            XCTAssertThrowsError(try ApplePayCapture(amount: amount, merchant: "Shop", currency: "CAD", accountID: account.id))
        }
        XCTAssertThrowsError(try ApplePayCapture(amount: "1", merchant: " ", currency: "CAD", accountID: account.id))
        XCTAssertThrowsError(try ApplePayCapture(amount: "1", merchant: "Shop", currency: "XXX", accountID: account.id))
    }
    // Existing statement matching must still recognize a captured purchase on the same account.
    func testStatementMatchAndClearCategorization() throws {
        var data = FinanceData.demo()
        let account = try XCTUnwrap(data.accounts.first)
        let capture = try ApplePayCapture(amount: "15.25", merchant: "rent", currency: account.currency, accountID: account.id)
        try capture.apply(to: &data)
        XCTAssertEqual(data.transactions.last?.needsReview, false)
        let row = ImportRow(date: capture.date, merchant: capture.merchant, amount: capture.amount, kind: .expense, category: "Other", note: "", balance: nil)
        XCTAssertTrue(TransactionImport.duplicates([row], in: data, account: account.id).contains(row.id))
    }
    func testMissingAccountAndCurrencyDoNotMutateLedger() throws {
        var data = FinanceData.demo()
        let before = data
        let missing = try ApplePayCapture(amount: "1", merchant: "Shop", currency: "CAD", accountID: UUID())
        XCTAssertThrowsError(try missing.apply(to: &data))
        let account = try XCTUnwrap(data.accounts.first)
        let mismatch = try ApplePayCapture(amount: "1", merchant: "Shop", currency: account.currency == "USD" ? "CAD" : "USD", accountID: account.id)
        XCTAssertThrowsError(try mismatch.apply(to: &data))
        XCTAssertEqual(data, before)
    }
    func testConcurrentEncryptedFilesAndInterruptedCleanup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ApplePayInbox(folder: folder, key: SymmetricKey(size: .bits256))
        let account = UUID()
        let captures = try (0..<20).map { _ in try ApplePayCapture(amount: "1.25", merchant: "Private merchant", currency: "CAD", accountID: account) }
        let failures = NSLock()
        var errors: [Error] = []
        DispatchQueue.concurrentPerform(iterations: captures.count) { index in
            do { try inbox.save(captures[index]) }
            catch { failures.lock(); errors.append(error); failures.unlock() }
        }
        XCTAssertTrue(errors.isEmpty)
        let files = try inbox.files()
        XCTAssertEqual(files.count, captures.count)
        for file in files {
            let bytes = try Data(contentsOf: file)
            XCTAssertNil(bytes.range(of: Data("Private merchant".utf8)))
            XCTAssertTrue(captures.contains(try inbox.read(file)))
        }
        // A second import after commit but before cleanup is harmless.
        var data = FinanceData.demo()
        var entry = try inbox.read(files[0])
        entry.accountID = try XCTUnwrap(data.accounts.first?.id)
        try entry.apply(to: &data)
        let committed = data
        try entry.apply(to: &data)
        XCTAssertEqual(data, committed)
    }
}
