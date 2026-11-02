import Foundation
import CryptoKit

// Capture identity survives a crash between ledger commit and inbox cleanup.
struct ApplePayCapture: Codable, Equatable {
    var id = UUID()
    var amount: Int
    var merchant: String
    var date: Date
    var currency: String
    var accountID: UUID

    init(amount: String, merchant: String, date: Date = Date(), currency: String, accountID: UUID) throws {
        guard let cents = Money.parse(amount), cents > 0 else { throw FinanceError(message: "Enter a positive amount with at most two decimal places.") }
        self.amount = cents
        self.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        self.date = date
        self.currency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.accountID = accountID
        try validate()
    }
    func validate() throws {
        guard amount > 0, amount <= 100_000_000_00, !merchant.isEmpty, merchant.utf8.count <= 1000,
              date.timeIntervalSince1970.isFinite else { throw FinanceError(message: "Purchase details are incomplete or invalid. Check the Shortcut inputs.") }
        guard Currency.supported.contains(currency) else { throw FinanceError(message: "Unsupported purchase currency. Correct the currency in the automation.") }
    }
    func apply(to data: inout FinanceData) throws {
        // Do not use merchant/amount deduplication here: equal purchases may both be genuine.
        if data.transactions.contains(where: { $0.id == id }) { return }
        try validate()
        guard let account = data.accounts.first(where: { $0.id == accountID }) else { throw FinanceError(message: "Purchase account is missing. Restore that account or update the pending purchase account.") }
        guard account.currency == currency else { throw FinanceError(message: "Purchase currency does not match its account. Update the pending purchase account or currency.") }
        var next = data
        let row = ImportRow(date: date, merchant: merchant, amount: amount, kind: .expense, category: "Other", note: "Apple Pay", balance: nil)
        let suggestion = Categorization.local(row, in: next, accountID: accountID, currency: currency)
        let name = suggestion?.name ?? "Other"
        let category = suggestion?.categoryID.flatMap { next.category($0) } ?? Categorization.existing(name, in: next, currency: currency)
            ?? Category(name: name, symbol: CategoryCatalog.symbol(name), limit: 0, importKey: CategoryCatalog.key(name), currencyCode: currency)
        if !next.categories.contains(where: { $0.id == category.id }) { next.categories.append(category) }
        // Automatic category decisions must not teach themselves as human-confirmed history.
        next.transactions.append(Transaction(id: id, merchant: merchant, amount: amount, kind: .expense, date: date, accountID: accountID, categoryID: category.id, note: "Apple Pay", needsReview: suggestion == nil, automaticallyReviewed: suggestion != nil ? true : nil, captureSource: "applePay", originalApplePayCapture: self, statementConfirmed: false))
        next.isDemo = false
        RecurringBills.matchImports([id], in: &next)
        // Captured subscriptions use the same reminder discovery as statement imports.
        try RecurringBills.autoTrack(in: &next)
        try next.validate()
        data = next
    }
}

// Independent encrypted files avoid read/modify/write races between simultaneous Shortcuts runs.
struct ApplePayInbox {
    let folder: URL
    let key: SymmetricKey
    // Quarantine requires no decryption key, allowing recovery even if an inbox key is missing.
    static func quarantineFiles(in folder: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "encrypted" }
        guard !files.isEmpty else { return }
        let held = folder.appendingPathComponent("quarantine", isDirectory: true)
        try FileManager.default.createDirectory(at: held, withIntermediateDirectories: true)
        for file in files { try FileManager.default.moveItem(at: file, to: held.appendingPathComponent(file.lastPathComponent)) }
    }
    func files() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "encrypted" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func save(_ capture: ApplePayCapture) throws {
        try capture.validate()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bytes = try LedgerCipher.encrypt(JSONEncoder().encode(capture), key: key)
        let url = folder.appendingPathComponent(capture.id.uuidString).appendingPathExtension("encrypted")
        #if os(iOS)
        try bytes.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try bytes.write(to: url, options: .atomic)
        #endif
        var directory = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }
    func read(_ url: URL) throws -> ApplePayCapture {
        try JSONDecoder().decode(ApplePayCapture.self, from: LedgerCipher.decrypt(Data(contentsOf: url), key: key))
    }
    func reassign(_ url: URL, to account: Account) throws {
        // Correct only a file owned by this inbox; held purchases must remain held until explicit release.
        guard url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else {
            throw FinanceError(message: "This purchase does not belong to the selected inbox.")
        }
        var capture = try read(url)
        guard url.lastPathComponent == capture.id.uuidString + ".encrypted" else {
            throw FinanceError(message: "Purchase file identity does not match its capture.")
        }
        guard account.currency == capture.currency else {
            throw FinanceError(message: "Choose an account in \(capture.currency). Changing accounts cannot convert the purchase currency.")
        }
        capture.accountID = account.id
        // An atomic encrypted replacement preserves the original file if validation or writing fails.
        try save(capture)
    }
}
