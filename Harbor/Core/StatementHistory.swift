import Foundation

// Receipts contain selected import metadata, never the source document or a filesystem path.
struct StatementImportRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var importedAt = Date()
    var filename: String
    var accountID: UUID
    var accountName: String
    var currency: String
    var firstDate: Date
    var lastDate: Date
    var openingBalance: Int?
    var closingBalance: Int?
    var totalRows: Int
    var addedRows: Int
    var matchedRows: Int
    var duplicatesSkipped: Int
    var deselectedRows: Int
    // IDs survive edits; deleted entries are allowed to disappear without erasing the historical receipt.
    var addedTransactionIDs: [UUID]
    var matchedTransactionIDs: [UUID]
}

// Store a civil closing day so changing the device time zone cannot change the statement's date.
struct StatementBalanceCheck: Identifiable, Codable, Equatable {
    var id = UUID()
    var savedAt = Date()
    var accountID: UUID
    var accountName: String
    var currency: String
    var closingDay: String
    var statementBalance: Int
}

enum StatementReconciliation {
    struct Result {
        var ledgerBalance: Int
        var statementBalance: Int
        var entries: [Transaction]
        var provisional: [Transaction]
        // Positive means Harbor is higher than the statement, in the account's native minor units.
        var difference: Int { ledgerBalance - statementBalance }
    }
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func calculate(_ check: StatementBalanceCheck, in data: FinanceData) throws -> Result {
        guard (-100_000_000_00...100_000_000_00).contains(check.statementBalance),
              let account = data.accounts.first(where: { $0.id == check.accountID }), account.currency == check.currency,
              let date = TransactionImport.date(check.closingDay),
              let end = Calendar.current.date(byAdding: .day, value: 1, to: date) else {
            throw FinanceError(message: "Choose an existing account and a valid statement closing date.")
        }
        // Use an exclusive next-day boundary, including late-day purchases and respecting daylight saving.
        let entries = data.transactions.filter { $0.accountID == account.id && $0.date < end }
        return Result(ledgerBalance: account.openingBalance + entries.reduce(0) { $0 + $1.signedAmount },
                      statementBalance: check.statementBalance, entries: entries,
                      provisional: entries.filter { ($0.captureSource == "applePay" || $0.originalApplePayCapture != nil || $0.note == "Apple Pay") && $0.statementConfirmed != true })
    }
}

extension FinanceData {
    // Metadata requires version 3 so older apps reject rather than silently drop audit records on save.
    var requiredVersion: Int { !(statementImports ?? []).isEmpty || !(statementBalanceChecks ?? []).isEmpty ? 3 : 2 }
    // A comparison from a removed account or another currency cannot choose the next destination.
    var mostRecentStatementAccountID: UUID? {
        (statementBalanceChecks ?? []).sorted { $0.savedAt > $1.savedAt }.first { check in
            accounts.contains { $0.id == check.accountID && $0.currency == check.currency }
        }?.accountID
    }
    mutating func saveStatementCheck(_ check: StatementBalanceCheck) throws {
        var next = self
        _ = try StatementReconciliation.calculate(check, in: next)
        var checks = next.statementBalanceChecks ?? []
        if let index = checks.firstIndex(where: { $0.accountID == check.accountID && $0.closingDay == check.closingDay }) {
            var replacement = check; replacement.id = checks[index].id
            checks[index] = replacement
        } else { checks.append(check) }
        next.statementBalanceChecks = checks
        next.version = max(next.version, next.requiredVersion)
        try next.validate()
        self = next
    }
    func validateStatementHistory() throws {
        let records = statementImports ?? [], checks = statementBalanceChecks ?? []
        let cap = 100_000_000_00
        guard records.count <= 10_000, checks.count <= 5_000,
              Set(records.map(\.id)).count == records.count, Set(checks.map(\.id)).count == checks.count else {
            throw FinanceError(message: "Invalid or oversized statement history.")
        }
        for record in records {
            let counts = [record.addedRows, record.matchedRows, record.duplicatesSkipped, record.deselectedRows]
            guard !record.filename.isEmpty, record.filename.utf8.count <= 1_000,
                  !record.filename.contains("/"), !record.filename.contains("\\"),
                  !record.accountName.isEmpty, record.accountName.utf8.count <= 1_000, Currency.supported.contains(record.currency),
                  record.importedAt.timeIntervalSince1970.isFinite,
                  record.firstDate.timeIntervalSince1970.isFinite, record.lastDate.timeIntervalSince1970.isFinite,
                  record.firstDate <= record.lastDate, (1...TransactionImport.maximumRows).contains(record.totalRows),
                  counts.allSatisfy({ (0...TransactionImport.maximumRows).contains($0) }), counts.reduce(0, +) == record.totalRows,
                  record.addedTransactionIDs.count <= 2 * record.addedRows,
                  record.addedTransactionIDs.count >= record.addedRows,
                  record.matchedTransactionIDs.count == record.matchedRows,
                  Set(record.addedTransactionIDs + record.matchedTransactionIDs).count == record.addedTransactionIDs.count + record.matchedTransactionIDs.count,
                  record.openingBalance.map({ (-cap...cap).contains($0) }) ?? true,
                  record.closingBalance.map({ (-cap...cap).contains($0) }) ?? true else {
                throw FinanceError(message: "Invalid statement import receipt.")
            }
        }
        var days = Set<String>()
        for check in checks {
            guard !check.accountName.isEmpty, check.accountName.utf8.count <= 1_000, Currency.supported.contains(check.currency),
                  check.savedAt.timeIntervalSince1970.isFinite, TransactionImport.date(check.closingDay) != nil,
                  (-cap...cap).contains(check.statementBalance), days.insert(check.accountID.uuidString + check.closingDay).inserted else {
                throw FinanceError(message: "Invalid statement balance comparison.")
            }
        }
    }
}

extension TransactionImport {
    // Commit the rows and receipt together; any validation/persistence failure leaves both unchanged.
    static func applyWithHistory(_ rows: [ImportRow], batch: ImportBatch, filename: String, to data: inout FinanceData,
                                 accountID: UUID?, newAccount: Account?, removeDemo: Bool,
                                 allowMatchingNewAccount: Bool = false, currencyCode: String, autoSavings: Bool = false,
                                 savingsAccountID: UUID? = nil) throws {
        let sourceIDs = Set(batch.rows.map(\.id)), selectedIDs = Set(rows.map(\.id))
        guard !batch.rows.isEmpty, batch.rows.count <= maximumRows, sourceIDs.count == batch.rows.count,
              selectedIDs.count == rows.count, selectedIDs.isSubset(of: sourceIDs),
              batch.currencyCode == nil || batch.currencyCode == currencyCode,
              batch.rows.allSatisfy({ $0.currencyCode == nil || $0.currencyCode == currencyCode }) else {
            throw FinanceError(message: "The import selection changed. Read the statement again.")
        }
        let destination = newAccount?.id ?? accountID
        let skipped = duplicates(batch.rows, in: data, account: accountID).subtracting(selectedIDs).count
        var next = data
        if rows.isEmpty {
            // A duplicate-only import can be recorded without creating accounts or changing financial records.
            guard newAccount == nil, !removeDemo, let accountID,
                  data.accounts.contains(where: { $0.id == accountID && $0.currency == currencyCode }), skipped > 0 else {
                throw FinanceError(message: "Select transactions or choose the existing account to record skipped duplicates.")
            }
        } else {
            try apply(rows, to: &next, accountID: accountID, newAccount: newAccount, removeDemo: removeDemo,
                      allowMatchingNewAccount: allowMatchingNewAccount, currencyCode: currencyCode,
                      autoSavings: autoSavings, savingsAccountID: savingsAccountID)
        }
        guard let account = next.accounts.first(where: { $0.id == destination }),
              let first = batch.rows.map(\.date).min(), let last = batch.rows.map(\.date).max() else {
            throw FinanceError(message: "Choose a valid statement account.")
        }
        let previousIDs = Set(data.transactions.map(\.id))
        let matches = rows.compactMap(\.reconcileTransactionID)
        let name = URL(fileURLWithPath: filename).lastPathComponent
        let receipt = StatementImportRecord(filename: name, accountID: account.id, accountName: account.name, currency: account.currency,
            firstDate: first, lastDate: last, openingBalance: batch.openingBalance, closingBalance: batch.closingBalance,
            totalRows: batch.rows.count, addedRows: rows.count - matches.count, matchedRows: matches.count,
            duplicatesSkipped: skipped, deselectedRows: batch.rows.count - rows.count - skipped,
            addedTransactionIDs: next.transactions.filter { !previousIDs.contains($0.id) }.map(\.id), matchedTransactionIDs: matches)
        next.statementImports = (next.statementImports ?? []) + [receipt]
        next.version = max(next.version, next.requiredVersion)
        try next.validate()
        data = next
    }
}
