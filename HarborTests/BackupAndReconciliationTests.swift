import XCTest
import CryptoKit
@testable import HarborCore

final class BackupAndReconciliationTests: XCTestCase {
    // Audit real Files exports from two QA simulators; recovery keys belong only to fictional test ledgers.
    func testVerifyOptionalDeviceMigrationExports() throws {
        guard let path = ProcessInfo.processInfo.environment["HARBOR_BACKUP_AUDIT_DIR"] else {
            throw XCTSkip("Requires real QA simulator exports staged in HARBOR_BACKUP_AUDIT_DIR.")
        }
        let folder = URL(fileURLWithPath: path)
        func ledger(_ name: String) throws -> FinanceData {
            let bytes = try Data(contentsOf: folder.appendingPathComponent(name + ".harborbackup"))
            let key = try String(contentsOf: folder.appendingPathComponent(name + "-key.txt"), encoding: .utf8)
            return try PortableBackup.decode(bytes, recoveryKey: key)
        }
        let source = try ledger("Harbor-device-migration")
        XCTAssertEqual(source.name, "Migration Test")
        XCTAssertFalse(source.accounts.isEmpty); XCTAssertFalse(source.transactions.isEmpty)
        XCTAssertFalse(source.categories.isEmpty); XCTAssertFalse(source.goals.isEmpty); XCTAssertFalse(source.bills.isEmpty)
        // Equatable compares every persisted field, including IDs, corrections, schedules, and balances' inputs.
        XCTAssertEqual(try ledger("Harbor-after-update"), source)
        XCTAssertEqual(try ledger("Harbor-restored-roundtrip"), source)
        let summary: [String: Any] = ["accounts": source.accounts.count, "transactions": source.transactions.count,
            "categories": source.categories.count, "goals": source.goals.count, "bills": source.bills.count,
            "balances": source.accounts.map { ["name": $0.name, "currency": $0.currency, "minorUnits": source.balance($0.id)] as [String: Any] }]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("verified-ledger-summary.json"), options: .atomic)
    }
    // A changed posting date/merchant/final amount is an explicit confirmation, including across months.
    func testMonthBoundaryPostingAndCaptureRetryAfterRecovery() throws {
        var data = FinanceData(isDemo: false)
        let account = Account(name: "Card", openingBalance: 10_000)
        data.accounts = [account]
        let calendar = Calendar.current
        let tapDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 23)))
        let postedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12)))
        let capture = try ApplePayCapture(amount: "10", merchant: "Restaurant", date: tapDate, currency: "CAD", accountID: account.id)
        try capture.apply(to: &data)
        var row = ImportRow(date: postedDate, merchant: "RESTAURANT POSTED", amount: 1_200, kind: .expense, category: "Other", note: "Statement", balance: nil)
        XCTAssertNil(TransactionImport.exactCapture(row, in: data, account: account.id))
        XCTAssertEqual(TransactionImport.captureCandidates(row, in: data, account: account.id).map(\.id), [capture.id])
        row.reconcileTransactionID = capture.id
        try TransactionImport.apply([row], to: &data, accountID: account.id, newAccount: nil, removeDemo: false)
        let key = String(repeating: "AB", count: 32)
        var recovered = try PortableBackup.decode(PortableBackup.encrypt(data, recoveryKey: key), recoveryKey: key)
        try capture.apply(to: &recovered)
        XCTAssertEqual(recovered, data)
        XCTAssertEqual(recovered.transactions.count, 1)
        XCTAssertEqual(recovered.balance(account.id), 8_800)
        XCTAssertEqual(recovered.transactions.first?.originalApplePayCapture, capture)
        XCTAssertTrue(TransactionImport.duplicates([row], in: recovered, account: account.id).contains(row.id))
        XCTAssertEqual(recovered.total(.expense, in: tapDate), 0)
        XCTAssertEqual(recovered.total(.expense, in: postedDate), 1_200)
    }
    // Equal genuine taps remain separate; confirming both statements never collapses their identities.
    func testIdenticalPurchasesConfirmSeparatelyAndRemainRepeatImportDuplicates() throws {
        var (data, capture, row) = try fixture()
        let second = try ApplePayCapture(amount: "12.34", merchant: capture.merchant, date: capture.date, currency: capture.currency, accountID: capture.accountID)
        try second.apply(to: &data)
        let count = data.transactions.count
        let balance = data.balance(capture.accountID)
        row.reconcileTransactionID = capture.id
        var other = row; other.id = UUID(); other.reconcileTransactionID = second.id
        try TransactionImport.apply([row, other], to: &data, accountID: capture.accountID, newAccount: nil, removeDemo: false)
        XCTAssertEqual(data.transactions.count, count)
        XCTAssertEqual(data.balance(capture.accountID), balance)
        XCTAssertEqual(TransactionImport.duplicates([row, other], in: data, account: capture.accountID), [row.id, other.id])
        XCTAssertTrue(data.transactions.filter { $0.id == capture.id || $0.id == second.id }.allSatisfy { $0.statementConfirmed == true })
    }
    // Recovery works without the original device key; ciphertext and version markers fail closed.
    func testPortableBackupRecoveryAndTampering() throws {
        let ledger = FinanceData.demo()
        let key = PortableBackup.recoveryKey()
        XCTAssertEqual(key.count, 64)
        let first = try PortableBackup.encrypt(ledger, recoveryKey: key)
        let second = try PortableBackup.encrypt(ledger, recoveryKey: key)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(String(decoding: first, as: UTF8.self).contains(ledger.name))
        XCTAssertEqual(try PortableBackup.decode(first, recoveryKey: key), ledger)
        XCTAssertEqual(try PortableBackup.decode(JSONEncoder().encode(ledger)), ledger)
        XCTAssertThrowsError(try PortableBackup.decode(first, recoveryKey: PortableBackup.recoveryKey()))
        var damaged = first; damaged[damaged.count - 1] ^= 1
        XCTAssertThrowsError(try PortableBackup.decode(damaged, recoveryKey: key))
        XCTAssertThrowsError(try PortableBackup.decode(Data("HARBOR-BACKUP-2\n".utf8) + first))
        XCTAssertThrowsError(try PortableBackup.decode(Data("HARBOR-BACKUP-1\ninvalid".utf8), recoveryKey: key))
        XCTAssertThrowsError(try PortableBackup.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try PortableBackup.key(String(repeating: "Z", count: 64)))
        XCTAssertThrowsError(try PortableBackup.decode(Data(repeating: 0, count: PortableBackup.maximumBytes + 1)))
    }
    func testQuarantineExcludesAutomaticDrainAndPreservesUnreadableFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ApplePayInbox(folder: folder, key: SymmetricKey(size: .bits256))
        let capture = try ApplePayCapture(amount: "1", merchant: "Held purchase", currency: "CAD", accountID: UUID())
        try inbox.save(capture)
        let broken = folder.appendingPathComponent("broken.encrypted")
        try Data("unreadable".utf8).write(to: broken)
        try ApplePayInbox.quarantineFiles(in: folder)
        XCTAssertTrue(try inbox.files().isEmpty)
        let held = ApplePayInbox(folder: folder.appendingPathComponent("quarantine"), key: inbox.key)
        XCTAssertEqual(try held.files().count, 2)
        let valid = try XCTUnwrap(held.files().first { $0.lastPathComponent == capture.id.uuidString + ".encrypted" })
        XCTAssertEqual(try held.read(valid), capture)
        XCTAssertThrowsError(try held.read(held.folder.appendingPathComponent("broken.encrypted")))
        // Repeated quarantine never consumes held records or exposes them to automatic import.
        try ApplePayInbox.quarantineFiles(in: folder)
        XCTAssertEqual(try held.files().count, 2)
    }
    // Optional QA artifacts contain only fictional data and a deliberately public test recovery key.
    func testWriteOptionalSimulatorFixtures() throws {
        guard let path = ProcessInfo.processInfo.environment["HARBOR_BACKUP_FIXTURE_DIR"] else { return }
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var data = FinanceData.demo(); data.name = "Restored QA ledger"
        let bytes = try PortableBackup.encrypt(data, recoveryKey: String(repeating: "AB", count: 32))
        try bytes.write(to: folder.appendingPathComponent("Harbor-encrypted-QA.harborbackup"))
        try JSONEncoder().encode(data).write(to: folder.appendingPathComponent("Harbor-legacy-QA.json"))
    }
    private func fixture() throws -> (FinanceData, ApplePayCapture, ImportRow) {
        var data = FinanceData.demo()
        let account = try XCTUnwrap(data.accounts.first)
        let capture = try ApplePayCapture(amount: "12.34", merchant: "Capture shop", date: Date(timeIntervalSince1970: 1_780_000_000), currency: account.currency, accountID: account.id)
        try capture.apply(to: &data)
        let row = ImportRow(date: capture.date, merchant: capture.merchant, amount: capture.amount, kind: .expense, category: "Other", note: "Statement", balance: nil)
        return (data, capture, row)
    }
    func testConfirmationPreservesIdentityAndManualCategoryAndRepeatDetection() throws {
        var (data, capture, row) = try fixture()
        let index = try XCTUnwrap(data.transactions.firstIndex { $0.id == capture.id })
        data.transactions[index].categoryManuallySet = true
        let category = data.transactions[index].categoryID
        let count = data.transactions.count
        XCTAssertEqual(TransactionImport.exactCapture(row, in: data, account: capture.accountID), capture.id)
        row.reconcileTransactionID = capture.id
        row.merchant = "Posted merchant"; row.amount += 200; row.date.addTimeInterval(86_400)
        try TransactionImport.apply([row], to: &data, accountID: capture.accountID, newAccount: nil, removeDemo: false)
        XCTAssertEqual(data.transactions.count, count)
        let posted = data.transactions[index]
        XCTAssertEqual(posted.id, capture.id)
        XCTAssertEqual(posted.originalApplePayCapture, capture)
        XCTAssertEqual(posted.statementConfirmed, true)
        XCTAssertEqual(posted.categoryID, category)
        XCTAssertEqual(posted.categoryManuallySet, true)
        XCTAssertEqual(posted.amount, row.amount)
        XCTAssertTrue(TransactionImport.duplicates([row], in: data, account: capture.accountID).contains(row.id))
        XCTAssertTrue(TransactionImport.captureCandidates(row, in: data, account: capture.accountID).isEmpty)
    }
    func testAmbiguityCurrencyAndRepeatedPurchaseSafety() throws {
        var (data, capture, row) = try fixture()
        let second = try ApplePayCapture(amount: "12.34", merchant: capture.merchant, date: capture.date, currency: capture.currency, accountID: capture.accountID)
        try second.apply(to: &data)
        XCTAssertNil(TransactionImport.exactCapture(row, in: data, account: capture.accountID))
        XCTAssertEqual(TransactionImport.captureCandidates(row, in: data, account: capture.accountID).count, 2)
        row.currencyCode = "EUR"
        XCTAssertTrue(TransactionImport.captureCandidates(row, in: data, account: capture.accountID).isEmpty)
        row.currencyCode = capture.currency
        XCTAssertTrue(TransactionImport.captureCandidates(row, in: data, account: UUID()).isEmpty)
        row.date.addTimeInterval(4 * 86_400)
        XCTAssertTrue(TransactionImport.captureCandidates(row, in: data, account: capture.accountID).isEmpty)
    }
    func testManualEditsRetainCaptureProvenance() throws {
        var (data, capture, _) = try fixture()
        let index = try XCTUnwrap(data.transactions.firstIndex { $0.id == capture.id })
        let old = data.transactions[index]
        let edit = Transaction(id: old.id, merchant: "My corrected merchant", amount: old.amount, kind: old.kind, date: old.date, accountID: old.accountID, categoryID: old.categoryID, note: "My note", categoryManuallySet: true)
        try data.replaceTransaction(edit)
        XCTAssertEqual(data.transactions[index].originalApplePayCapture, capture)
        XCTAssertEqual(data.transactions[index].captureSource, "applePay")
        XCTAssertEqual(data.transactions[index].note, "My note")
    }
    func testInvalidReconciliationIsAtomicAndCannotReuseOneCapture() throws {
        var (data, capture, row) = try fixture()
        row.reconcileTransactionID = capture.id
        var duplicate = row; duplicate.id = UUID()
        let before = data
        XCTAssertThrowsError(try TransactionImport.apply([row, duplicate], to: &data, accountID: capture.accountID, newAccount: nil, removeDemo: false))
        XCTAssertEqual(data, before)
        row.reconcileTransactionID = UUID()
        XCTAssertThrowsError(try TransactionImport.apply([row], to: &data, accountID: capture.accountID, newAccount: nil, removeDemo: false))
        XCTAssertEqual(data, before)
    }
    func testLegacyCaptureProvenanceAndBackupCompatibility() throws {
        var (data, capture, row) = try fixture()
        let index = try XCTUnwrap(data.transactions.firstIndex { $0.id == capture.id })
        data.transactions[index].captureSource = nil
        data.transactions[index].originalApplePayCapture = nil
        data.transactions[index].statementConfirmed = nil
        let legacy = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(TransactionImport.exactCapture(row, in: legacy, account: capture.accountID), capture.id)
        row.reconcileTransactionID = capture.id
        try TransactionImport.apply([row], to: &data, accountID: capture.accountID, newAccount: nil, removeDemo: false)
        XCTAssertEqual(data.transactions[index].originalApplePayCapture?.id, capture.id)
        XCTAssertEqual(try PortableBackup.decode(PortableBackup.encrypt(data, recoveryKey: String(repeating: "AB", count: 32)), recoveryKey: String(repeating: "AB", count: 32)), data)
    }
}
