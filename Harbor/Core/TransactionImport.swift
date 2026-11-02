import Foundation

// Import candidates remain separate from saved records until the user confirms the preview.
struct ImportRow: Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var merchant: String
    var amount: Int
    var kind: TransactionKind
    var category: String
    var note: String
    var balance: Int?
    var currencyCode: String? = nil
    // Preview-only provenance and manual overrides never affect transaction identity or financial validation.
    var reconcileTransactionID: UUID? = nil
    var manualCategory = false
    var sourceCategory: String? = nil
    var suggestedCategoryID: UUID? = nil
    var categoryReason: String? = nil
    // Bind model approval to the exact fields checked, so preview edits invalidate stale evidence.
    var clearCategoryEvidence: [String]? = nil
    var savingsTransfer: Bool? = nil
    var isSavingsTransfer: Bool {
        if let savingsTransfer { return savingsTransfer && kind == .expense }
        return kind == .expense && FinanceData.isSavingsDescription(merchant)
    }
    var signedAmount: Int { kind == .income ? amount : -amount }
}
struct ImportBatch {
    var rows: [ImportRow]
    var openingBalance: Int?
    var closingBalance: Int?
    var usedOCR = false
    var currencyCode: String? = nil
    var usedDocumentRecognition = false
    var currency: String { currencyCode ?? "CAD" }
    var savingsOut: Int { rows.filter(\.isSavingsTransfer).reduce(0) { $0 + $1.amount } }
    // Direction is preserved, but an internal transfer needs a richer model than expense/income.
    var hasPossibleTransfers: Bool {
        rows.contains { row in
            let category = row.category.lowercased(), merchant = row.merchant.lowercased()
            return category.contains("savings") || category.contains("transfer") || merchant.contains("transfer")
        }
    }
    var income: Int { rows.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount } }
    var expenses: Int { rows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }
}

enum TransactionImport {
    static let maximumBytes = 25_000_000
    static let maximumRows = 10_000
    static func date(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        guard let date = f.date(from: text), f.string(from: date) == text else { return nil }
        return date
    }
    static func cents(_ text: String) -> Int? {
        // Accept CAD formatting while rejecting malformed grouping, exponents, and fractional cents.
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Normalize one explicit negative sign or accounting parentheses around a currency amount.
        var negative = false
        if value.hasPrefix("(") && value.hasSuffix(")") { negative = true; value = String(value.dropFirst().dropLast()) }
        if value.hasPrefix("-") { guard !negative else { return nil }; negative = true; value.removeFirst() }
        for prefix in ["US$", "CA$", "C$", "$", "£", "€"] where value.hasPrefix(prefix) { value.removeFirst(prefix.count); break }
        if value.hasPrefix("-") { guard !negative else { return nil }; negative = true; value.removeFirst() }
        if value.contains(",") {
            guard value.range(of: #"^-?\d{1,3}(,\d{3})+(\.\d{1,2})?$"#, options: .regularExpression) != nil else { return nil }
            value = value.replacingOccurrences(of: ",", with: "")
        }
        return Money.parse((negative ? "-" : "") + value, allowNegative: true)
    }
    static func csv(_ bytes: Data) throws -> ImportBatch {
        guard bytes.count <= maximumBytes, let text = String(data: bytes, encoding: .utf8) else {
            throw FinanceError(message: "Choose a UTF-8 CSV no larger than 25 MB.")
        }
        let table = try CSVReader.read(text)
        guard let headers = table.first, table.count > 1 else { throw FinanceError(message: "The CSV has no transaction rows.") }
        // Currency suffixes do not change a column's meaning; retain duplicate-name rejection after normalization.
        let detectedCurrency = try Currency.detect(headers.joined(separator: " "))
        let names = headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: #"\s*\((cad|usd|gbp|eur|aud|nzd|chf|sgd|hkd)\)$"#, with: "", options: .regularExpression) }
        guard Set(names).count == names.count else { throw FinanceError(message: "CSV column names must be unique.") }
        func column(_ alternatives: [String]) -> Int? { alternatives.compactMap { names.firstIndex(of: $0) }.first }
        guard let dateColumn = column(["date", "transaction date"]), let description = column(["description", "merchant", "payee"]) else {
            throw FinanceError(message: "CSV requires Date and Description columns (dates must be YYYY-MM-DD).")
        }
        let debit = column(["debit", "withdrawal", "withdrawals", "money out"])
        let credit = column(["credit", "deposit", "deposits", "money in"])
        let amount = column(["amount", "signed amount"])
        guard (debit != nil && credit != nil) || amount != nil else {
            throw FinanceError(message: "CSV requires Debit and Credit columns, or a signed Amount column (negative expenses, positive income).")
        }
        let category = column(["category"]), memo = column(["memo", "note", "notes"])
        let balance = column(["balance", "running balance"]), currency = column(["currency"])
        let method = column(["payment method"])
        var rows: [ImportRow] = []
        var statementCurrency = detectedCurrency
        for (offset, fields) in table.dropFirst().enumerated() {
            try Task.checkCancellation()
            let line = offset + 2
            guard fields.count == headers.count else { throw FinanceError(message: "CSV row \(line) has the wrong number of columns.") }
            func value(_ index: Int?) -> String { index.map { fields[$0].trimmingCharacters(in: .whitespacesAndNewlines) } ?? "" }
            guard let day = date(value(dateColumn)), !value(description).isEmpty else { throw FinanceError(message: "CSV row \(line) has an invalid date or empty description.") }
            if currency != nil && !value(currency).isEmpty && !Currency.supported.contains(value(currency).uppercased()) { throw FinanceError(message: "CSV row \(line) has an unsupported currency code.") }
            let rowCurrency = try Currency.detect(value(currency) + " " + value(amount) + " " + value(debit) + " " + value(credit) + " " + value(balance))
            if let rowCurrency {
                guard statementCurrency == nil || statementCurrency == rowCurrency else { throw FinanceError(message: "CSV row \(line) has a different currency. Split mixed-currency files before importing.") }
                statementCurrency = rowCurrency
            }
            let signed: Int
            if let debit, let credit {
                guard let out = cents(value(debit).isEmpty ? "0" : value(debit)), let incoming = cents(value(credit).isEmpty ? "0" : value(credit)), out >= 0, incoming >= 0, (out > 0) != (incoming > 0) else {
                    throw FinanceError(message: "CSV row \(line) must contain one positive debit or credit.")
                }
                signed = incoming - out
            } else {
                guard let parsed = cents(value(amount)), parsed != 0 else { throw FinanceError(message: "CSV row \(line) has an invalid signed amount.") }
                signed = parsed
            }
            let running = balance == nil ? nil : cents(value(balance))
            guard balance == nil || running != nil else { throw FinanceError(message: "CSV row \(line) has an invalid balance.") }
            rows.append(ImportRow(date: day, merchant: value(description), amount: abs(signed), kind: signed > 0 ? .income : .expense,
                                  category: value(category).isEmpty ? "Uncategorized" : value(category),
                                  note: [value(memo), value(method)].filter { !$0.isEmpty }.joined(separator: " · "), balance: running, currencyCode: statementCurrency))
        }
        for i in rows.indices { rows[i].currencyCode = statementCurrency }
        var batch = ImportBatch(rows: rows, currencyCode: statementCurrency)
        if let first = rows.first, let balance = first.balance { batch.openingBalance = balance - first.signedAmount }
        batch.closingBalance = rows.last?.balance
        try validate(batch)
        return batch
    }
    static func validate(_ batch: ImportBatch) throws {
        guard !batch.rows.isEmpty, batch.rows.count <= maximumRows else { throw FinanceError(message: "Import must contain between 1 and 10,000 transactions.") }
        guard batch.currencyCode == nil || Currency.supported.contains(batch.currency) else { throw FinanceError(message: "Unsupported statement currency.") }
        guard batch.rows.allSatisfy({ $0.currencyCode == nil || $0.currencyCode == batch.currency }) else { throw FinanceError(message: "Statement contains mixed currencies.") }
        var running = batch.openingBalance
        var previous: Date?
        for row in batch.rows {
            guard row.amount > 0, row.amount <= 100_000_000_00, !row.merchant.isEmpty else { throw FinanceError(message: "An imported transaction has an invalid description or amount.") }
            guard previous == nil || row.date >= previous! else { throw FinanceError(message: "Transactions must be ordered oldest to newest. Export an ascending statement and try again.") }
            if let current = running {
                let next = current.addingReportingOverflow(row.signedAmount)
                guard !next.overflow, row.balance == nil || row.balance == next.partialValue else {
                    throw FinanceError(message: "Running balance does not reconcile at \(row.merchant). No records were imported.")
                }
                running = next.partialValue
            }
            previous = row.date
        }
        guard batch.closingBalance == nil || running == batch.closingBalance else { throw FinanceError(message: "The statement's closing balance does not reconcile.") }
    }
    private static func signature(date: Date, merchant: String, amount: Int, kind: TransactionKind) -> String {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let name = merchant.uppercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)|\(name)|\(amount)|\(kind.rawValue)"
    }
    static func duplicates(_ rows: [ImportRow], in data: FinanceData, account: UUID?) -> Set<UUID> {
        // Match occurrences, not just a set: two equal purchases in a statement remain two records.
        var counts: [String: Int] = [:]
        for t in data.transactions where t.accountID == account {
            counts[signature(date: t.date, merchant: t.merchant, amount: t.amount, kind: t.kind), default: 0] += 1
        }
        var result = Set<UUID>()
        for row in rows {
            guard row.currencyCode == nil || account.map({ data.currency($0) == row.currencyCode }) == true else { continue }
            let key = signature(date: row.date, merchant: row.merchant, amount: row.amount, kind: row.kind)
            if counts[key, default: 0] > 0 { result.insert(row.id); counts[key, default: 0] -= 1 }
        }
        let usedExact = Set(rows.filter { result.contains($0.id) }.map { signature(date: $0.date, merchant: $0.merchant, amount: $0.amount, kind: $0.kind) })
        var synthetic = data.transactions.filter { $0.accountID == account && $0.derivedTransfer == true && !usedExact.contains(signature(date: $0.date, merchant: $0.merchant, amount: $0.amount, kind: $0.kind)) }
        for row in rows where !result.contains(row.id) {
            guard row.currencyCode == nil || account.map({ data.currency($0) == row.currencyCode }) == true else { continue }
            guard (row.merchant + " " + row.category + " " + row.note).lowercased().contains("transfer") else { continue }
            let matches = synthetic.indices.filter { index in
                let t = synthetic[index]
                return t.amount == row.amount && t.kind == row.kind && Calendar.current.isDate(t.date, inSameDayAs: row.date)
            }
            if matches.count == 1 { result.insert(row.id); synthetic.remove(at: matches[0]) }
        }
        return result
    }
    // Account-level evidence catches repeat statements even while the destination is still "new account".
    struct AccountMatch: Identifiable {
        let account: Account
        let count: Int
        var id: UUID { account.id }
    }
    static func matchingAccounts(_ rows: [ImportRow], in data: FinanceData) -> [AccountMatch] {
        data.accounts.compactMap { account in
            guard rows.allSatisfy({ $0.currencyCode == nil || $0.currencyCode == account.currency }) else { return nil }
            let count = duplicates(rows, in: data, account: account.id).count
            return count > 0 ? AccountMatch(account: account, count: count) : nil
        }.sorted { $0.count == $1.count ? $0.account.name < $1.account.name : $0.count > $1.count }
    }
    static func suggestedAccount(_ rows: [ImportRow], in data: FinanceData) -> UUID? {
        // A few identical purchases are not enough to choose an account on the user's behalf.
        guard rows.count >= 3 else { return nil }
        let full = matchingAccounts(rows, in: data).filter { $0.count == rows.count }
        return full.count == 1 ? full[0].id : nil
    }
    // Candidate matching is bounded by account/currency; uncertain and changed amounts require a user choice.
    static func captureCandidates(_ row: ImportRow, in data: FinanceData, account: UUID?) -> [Transaction] {
        guard let account, row.kind == .expense, !row.isSavingsTransfer, row.currencyCode == nil || row.currencyCode == data.currency(account) else { return [] }
        return data.transactions.filter {
            $0.accountID == account && $0.kind == .expense && !$0.isTransfer &&
            ($0.captureSource == "applePay" || $0.note == "Apple Pay") && $0.statementConfirmed != true &&
            abs(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: $0.date), to: Calendar.current.startOfDay(for: row.date)).day ?? Int.max) <= 3
        }
    }
    static func exactCapture(_ row: ImportRow, in data: FinanceData, account: UUID?) -> UUID? {
        let matches = captureCandidates(row, in: data, account: account).filter {
            signature(date: $0.date, merchant: $0.merchant, amount: $0.amount, kind: $0.kind) ==
            signature(date: row.date, merchant: row.merchant, amount: row.amount, kind: row.kind)
        }
        return matches.count == 1 ? matches[0].id : nil
    }
    static func apply(_ rows: [ImportRow], to data: inout FinanceData, accountID: UUID?, newAccount: Account?, removeDemo: Bool, allowMatchingNewAccount: Bool = false, currencyCode: String? = nil, autoSavings: Bool = false, savingsAccountID: UUID? = nil) throws {
        guard !rows.isEmpty else { throw FinanceError(message: "Select at least one transaction.") }
        // Enforce the warning in the shared save path as well as the preview; failed saves stay atomic.
        if newAccount != nil && !removeDemo && !allowMatchingNewAccount && !matchingAccounts(rows, in: data).isEmpty {
            throw FinanceError(message: "These transactions already match an existing account. Select that account, or explicitly confirm creating a separate account in the import preview.")
        }
        var candidate = data
        candidate.version = max(candidate.version, 2)
        if removeDemo {
            guard candidate.isDemo, newAccount != nil else { throw FinanceError(message: "Demo removal requires a new import account.") }
            candidate.accounts = []; candidate.transactions = []; candidate.goals = []; candidate.bills = []
            // Explicit demo replacement also replaces its account-scoped statement history.
            candidate.statementImports = nil; candidate.statementBalanceChecks = nil
        }
        let destination: UUID
        if let newAccount { candidate.accounts.append(newAccount); destination = newAccount.id }
        else if let accountID, candidate.accounts.contains(where: { $0.id == accountID }) { destination = accountID }
        else { throw FinanceError(message: "Choose a valid import account.") }
        let previousIDs = Set(candidate.transactions.map(\.id))
        let destinationCurrency = candidate.currency(destination)
        if data.accounts.isEmpty || removeDemo { candidate.reportingCurrencyCode = destinationCurrency }
        guard currencyCode == nil || currencyCode == destinationCurrency,
              rows.allSatisfy({ $0.currencyCode == nil || $0.currencyCode == destinationCurrency }) else { throw FinanceError(message: "Statement currency does not match the destination account. Create or choose an account in the statement currency.") }
        let savingsDuplicates = duplicates(rows.filter(\.isSavingsTransfer), in: candidate, account: destination)
        guard !autoSavings || savingsDuplicates.isEmpty else { throw FinanceError(message: "A savings transfer is already recorded. Deselect duplicate transfers before saving.") }
        let reconciliationIDs = rows.compactMap(\.reconcileTransactionID)
        guard Set(reconciliationIDs).count == reconciliationIDs.count else { throw FinanceError(message: "Two statement rows cannot confirm the same Apple Pay purchase.") }
        for row in rows {
            if let target = row.reconcileTransactionID {
                guard !row.isSavingsTransfer,
                      captureCandidates(row, in: candidate, account: destination).contains(where: { $0.id == target }),
                      let index = candidate.transactions.firstIndex(where: { $0.id == target }) else {
                    throw FinanceError(message: "The Apple Pay match changed. Review the statement again.")
                }
                // Preserve identity, notes, original capture and authoritative manual categorization.
                if candidate.transactions[index].originalApplePayCapture == nil {
                    let old = candidate.transactions[index]
                    var capture = try ApplePayCapture(amount: Money.input(old.amount), merchant: old.merchant, date: old.date, currency: destinationCurrency, accountID: destination)
                    capture.id = old.id
                    candidate.transactions[index].originalApplePayCapture = capture
                }
                candidate.transactions[index].merchant = row.merchant
                candidate.transactions[index].date = row.date
                candidate.transactions[index].amount = row.amount
                candidate.transactions[index].captureSource = "applePay"
                candidate.transactions[index].statementConfirmed = true
                continue
            }
            // Reuse stable category identities, including the user's renamed categories.
            var name = row.manualCategory ? row.category : CategoryCatalog.name(row.category)
            if !row.manualCategory && name == "Utilities" && RecurringBills.key(row.merchant) == "rent" { name = "Rent" }
            let category: Category
            if !row.manualCategory, let id = row.suggestedCategoryID {
                guard let saved = candidate.category(id), saved.currency == destinationCurrency else { throw FinanceError(message: "A suggested category changed. Review the import again.") }
                category = saved
            } else if let existing = row.manualCategory
                ? candidate.categories.first(where: { $0.currency == destinationCurrency && CategoryCatalog.normalized($0.name) == CategoryCatalog.normalized(name) })
                : Categorization.existing(name, in: candidate, currency: destinationCurrency) { category = existing }
            else {
                category = Category(name: name.isEmpty ? "Other" : name, symbol: CategoryCatalog.symbol(name), limit: 0, importKey: CategoryCatalog.key(name), currencyCode: destinationCurrency == "CAD" ? nil : destinationCurrency)
                candidate.categories.append(category)
            }
            // Financial validation still runs below; only supported category decisions clear the review flag.
            let clear = Categorization.isClear(row, in: data, accountID: destination, currency: destinationCurrency)
            let entry = Transaction(merchant: row.merchant, amount: row.amount, kind: row.kind, date: row.date,
                                    accountID: destination, categoryID: category.id, note: row.note, needsReview: !clear, categoryManuallySet: row.manualCategory ? true : nil, automaticallyReviewed: clear && !row.manualCategory ? true : nil)
            candidate.transactions.append(entry)
            if autoSavings && row.isSavingsTransfer { try candidate.linkSavingsTransfer(entry.id, savingsAccountID: savingsAccountID) }
        }
        RecurringBills.matchImports(Set(candidate.transactions.map(\.id)).subtracting(previousIDs), in: &candidate)
        candidate.isDemo = false
        // Both CSV and PDF imports discover reminders without inserting another financial transaction.
        try RecurringBills.autoTrack(in: &candidate)
        try candidate.validate()
        data = candidate
    }
}

// RFC 4180 quoting: embedded commas, escaped quotes, multiline fields, CRLF, and a UTF-8 BOM.
enum CSVReader {
    static func read(_ source: String) throws -> [[String]] {
        let text = source.hasPrefix("\u{feff}") ? String(source.dropFirst()) : source
        var iterator = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").makeIterator()
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, closed = false
        var current = iterator.next()
        func finishRow() throws {
            try Task.checkCancellation()
            guard field.utf8.count <= 10_000, row.count < 100 else { throw FinanceError(message: "CSV exceeds the field or column limit.") }
            row.append(field)
            if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { rows.append(row) }
            guard rows.count <= TransactionImport.maximumRows + 1 else { throw FinanceError(message: "CSV exceeds 10,000 rows.") }
            row = []; field = ""; closed = false
        }
        while let c = current {
            current = iterator.next()
            guard field.utf8.count <= 10_000, row.count <= 100 else { throw FinanceError(message: "CSV fields must be at most 10,000 UTF-8 bytes, with at most 100 columns.") }
            if quoted {
                if c == "\"" {
                    if current == "\"" { field.append("\""); current = iterator.next() }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "," { row.append(field); field = ""; closed = false }
            else if c == "\n" { try finishRow() }
            else if c == "\"", field.isEmpty, !closed { quoted = true }
            else {
                guard !closed, c != "\"" else { throw FinanceError(message: "CSV has malformed quoting. No records were imported.") }
                field.append(c)
            }
        }
        guard !quoted else { throw FinanceError(message: "CSV contains an unterminated quoted field.") }
        if !field.isEmpty || !row.isEmpty || closed { try finishRow() }
        return rows
    }
}
