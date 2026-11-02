import Foundation

// Store emoji directly in the existing symbol field; old SF Symbol names and backups stay compatible.
enum HarborIcon {
    static func emoji(in input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 1, let first = value.unicodeScalars.first, first.properties.isEmoji else { return nil }
        // Bare digits are Unicode emoji candidates, but only their keycap sequences are pictorial icons.
        let pictorial = first.properties.isEmojiPresentation || first.value > 0x7F
            || value.unicodeScalars.contains { $0.value == 0x20E3 }
        return pictorial ? value : nil
    }
}

// Money is stored in integer cents so totals and budget arithmetic never round through Double.
struct Account: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var openingBalance: Int
    // Optional metadata keeps legacy encrypted ledgers and JSON backups in CAD.
    var currencyCode: String? = nil
    var savingsSourceAccountID: UUID? = nil
    var savingsReference: String? = nil
    var currency: String { currencyCode ?? "CAD" }
}
struct Category: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var limit: Int
    // Optional identity keeps category display-name edits compatible with older backups.
    var importKey: String? = nil
    var importAliases: [String]? = nil
    var currencyCode: String? = nil
    // Legacy positive limits remain manual; previously unset categories can use recorded history.
    var automaticBudget: Bool? = nil
    var usesAutomaticBudget: Bool { automaticBudget ?? (limit == 0) }
    var currency: String { currencyCode ?? "CAD" }
}
enum TransactionKind: String, Codable, CaseIterable { case expense, income }
struct Transaction: Identifiable, Codable, Equatable {
    var id = UUID()
    var merchant: String
    var amount: Int
    var kind: TransactionKind
    var date: Date
    var accountID: UUID
    var categoryID: UUID
    var note = ""
    var needsReview = false
    // Optional for compatibility with saved ledgers created before bill matching.
    var recurringBillID: UUID? = nil
    // A linked transfer retains its bank debit/credit direction but is excluded from income and spending.
    var transferAccountID: UUID? = nil
    var transferPairID: UUID? = nil
    var derivedTransfer: Bool? = nil
    // Explicit category corrections remain protected even while the transaction still needs review.
    var categoryManuallySet: Bool? = nil
    // Automatic approval is not a human-reviewed training example; optional for older backups.
    var automaticallyReviewed: Bool? = nil
    // Optional provenance keeps old ledgers readable and preserves the original tap after posting changes.
    var captureSource: String? = nil
    var originalApplePayCapture: ApplePayCapture? = nil
    var statementConfirmed: Bool? = nil
    var isTransfer: Bool { transferPairID != nil }
    var signedAmount: Int { kind == .income ? amount : -amount }
}
struct Goal: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var target: Int
    var saved: Int
    var accountID: UUID
    var deadline: Date
    var highPriority = false
}
struct Bill: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var amount: Int
    var due: Date
    var accountID: UUID
    var categoryID: UUID
    // Missing fields retain the original monthly, manually tracked bill behavior.
    var recurrence: BillFrequency? = nil
    var matchingMerchant: String? = nil
    var minimumAmount: Int? = nil
    var maximumAmount: Int? = nil
    var anchorDay: Int? = nil
    // Optional receipt metadata keeps existing saved bills and backups compatible.
    var lastPaidAt: Date? = nil
    // Detection provenance distinguishes a confirmed cadence from a single-charge estimate.
    var automaticallyDetected: Bool? = nil
    var needsScheduleReview: Bool? = nil
    var detectionReviewReason: String? = nil
    var frequency: BillFrequency { recurrence ?? .monthly }
    func isPaymentComplete(on date: Date = Date()) -> Bool {
        guard let paid = lastPaidAt, date >= paid else { return false }
        // Keep the completed occurrence visible until the next due day. Overdue catch-up
        // payments also stay completed for today instead of inviting an immediate duplicate.
        let calendar = Calendar.current
        return calendar.isDate(paid, inSameDayAs: date) || calendar.startOfDay(for: date) < calendar.startOfDay(for: due)
    }
}
struct FinanceError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
struct FinanceData: Codable, Equatable {
    // Version 2 prevents older CAD-only builds from misreading currency and linked-transfer records.
    var version = 2
    var name = "Maya"
    var isDemo = true
    var accounts: [Account] = []
    var categories: [Category] = []
    var transactions: [Transaction] = []
    var goals: [Goal] = []
    var bills: [Bill] = []
    var reportingCurrencyCode: String? = nil
    // Account-scoped dismissals prevent deleted reminders reappearing on every import or unlock.
    var ignoredRecurringMerchants: [String]? = nil
    // Optional audit metadata lets existing version 1/2 ledgers decode without inventing old import history.
    var statementImports: [StatementImportRecord]? = nil
    var statementBalanceChecks: [StatementBalanceCheck]? = nil
    // Optional history keeps older ledgers readable and travels inside the encrypted portable backup.
    var checkInStreak: CheckInStreak? = nil
    var reportingCurrency: String { reportingCurrencyCode ?? "CAD" }
    var currencies: [String] { Array(Set(accounts.map(\.currency) + [reportingCurrency])).sorted() }
    func currency(_ account: UUID) -> String { accounts.first { $0.id == account }?.currency ?? reportingCurrency }
    func netWorth(in currency: String) -> Int { accounts.filter { $0.currency == currency }.reduce(0) { $0 + balance($1.id) } }
    func reportingEntries(in month: Date) -> [Transaction] { entries(in: month).filter { currency($0.accountID) == reportingCurrency && !$0.isTransfer } }
    var reportingCategories: [Category] { categories.filter { $0.currency == reportingCurrency } }
    var reportingGoals: [Goal] { goals.filter { currency($0.accountID) == reportingCurrency } }


    func balance(_ id: UUID) -> Int {
        (accounts.first { $0.id == id }?.openingBalance ?? 0) + transactions.filter { $0.accountID == id }.reduce(0) { $0 + $1.signedAmount }
    }
    var netWorth: Int { netWorth(in: reportingCurrency) }
    var budget: Int { reportingCategories.reduce(0) { $0 + $1.limit } }
    func entries(in month: Date) -> [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
            .sorted { $0.date > $1.date }
    }
    func total(_ kind: TransactionKind, in month: Date, category: UUID? = nil) -> Int {
        reportingEntries(in: month).filter { $0.kind == kind && (category == nil || $0.categoryID == category) }.reduce(0) { $0 + $1.amount }
    }
    func allocated(_ account: UUID, excluding goal: UUID? = nil) -> Int {
        goals.filter { $0.accountID == account && $0.id != goal }.reduce(0) { $0 + $1.saved }
    }
    func accountName(_ id: UUID) -> String { accounts.first { $0.id == id }?.name ?? "Unknown account" }
    func category(_ id: UUID) -> Category? { categories.first { $0.id == id } }

    // Validate the entire candidate before saving; failed edits and imports leave the previous state intact.
    func validate() throws {
        func require(_ condition: Bool, _ text: String) throws { if !condition { throw FinanceError(message: text) } }
        let cap = 100_000_000_00
        try require(Currency.supported.contains(reportingCurrency), "Choose a supported reporting currency.")
        try require((1...3).contains(version), "This backup version is not supported.")
        try require(version >= requiredVersion || (version == 1 && requiredVersion == 2), "Statement history requires backup version 3.")
        try validateStatementHistory()
        try checkInStreak?.validate()
        try require(version != 1 || (reportingCurrency == "CAD" && accounts.allSatisfy { $0.currency == "CAD" } && categories.allSatisfy { $0.currency == "CAD" } && !transactions.contains(where: \.isTransfer)), "Currency and transfer records require backup version 2.")
        try require(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Enter your name.")
        try require(accounts.count <= 100 && categories.count <= 200 && transactions.count <= 100_000 && goals.count <= 500 && bills.count <= 500, "This backup exceeds the supported record limits.")
        try require(Set(accounts.map(\.id)).count == accounts.count && Set(categories.map(\.id)).count == categories.count && Set(transactions.map(\.id)).count == transactions.count && Set(goals.map(\.id)).count == goals.count && Set(bills.map(\.id)).count == bills.count, "Duplicate record identifiers in backup.")
        let accountIDs = Set(accounts.map(\.id)), categoryIDs = Set(categories.map(\.id))
        for a in accounts { try require(!a.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (-cap...cap).contains(a.openingBalance), "Enter an account name and a valid opening balance.") }
        for a in accounts {
            try require(Currency.supported.contains(a.currency), "Unsupported account currency.")
            if let source = a.savingsSourceAccountID { try require(source != a.id && accountIDs.contains(source) && currency(source) == a.currency, "Invalid linked savings account.") }
        }
        // A stored zero supports both derived automatic limits and explicit manual no-limit choices.
        for c in categories { try require(Currency.supported.contains(c.currency), "Unsupported budget currency."); try require(!c.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && c.limit >= 0 && c.limit <= cap, "Category names and nonnegative budget limits are required.") }
        for t in transactions {
            // Reject malformed source snapshots before restoring or performing financial calculations.
            if let original = t.originalApplePayCapture {
                try original.validate()
                try require(original.id == t.id, "Apple Pay capture identity does not match its transaction.")
            }
            try require(!t.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && t.amount > 0 && t.amount <= cap, "Enter a merchant and a positive amount.")
            try require(accountIDs.contains(t.accountID) && categoryIDs.contains(t.categoryID), "Choose a valid account and category.")
            try require(t.date.timeIntervalSince1970.isFinite, "Invalid transaction date.")
            try require(category(t.categoryID)?.currency == currency(t.accountID), "Account and category currencies must match.")
            try require((t.transferPairID == nil) == (t.transferAccountID == nil), "Incomplete transfer link.")
        }
        // Every internal transfer must balance in one currency, across exactly two distinct accounts.
        let pairs = Dictionary(grouping: transactions.filter(\.isTransfer), by: { $0.transferPairID! })
        for pair in pairs.values {
            try require(pair.count == 2, "A transfer requires two linked entries.")
            let a = pair[0], b = pair[1]
            try require(a.accountID != b.accountID && a.transferAccountID == b.accountID && b.transferAccountID == a.accountID && a.amount == b.amount && a.kind != b.kind && a.date == b.date && currency(a.accountID) == currency(b.accountID), "Transfer entries must balance in matching currencies.")
        }
        for g in goals {
            try require(!g.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && g.target > 0 && g.target <= cap && g.saved >= 0 && g.saved <= g.target, "Goal savings must be between zero and the target.")
            try require(accountIDs.contains(g.accountID), "Choose a funding account.")
            try require(g.deadline.timeIntervalSince1970.isFinite, "Invalid goal date.")
        }
        // Earmarking savings does not spend money or change net worth, and cannot exceed available funds.
        for a in accounts where allocated(a.id) > 0 { try require(allocated(a.id) <= balance(a.id), "Savings allocations exceed the balance in \(a.name). Release goal funds or choose another account first.") }
        for b in bills {
            try require(b.due.timeIntervalSince1970.isFinite, "Invalid bill date.")
            // Validate optional matching bounds from backups before arithmetic or calendar use.
            let low = b.minimumAmount ?? b.amount, high = b.maximumAmount ?? b.amount
            try require(low > 0 && high >= low && high <= cap, "Invalid recurring bill amount range.")
            try require(b.anchorDay == nil || (1...31).contains(b.anchorDay!), "Invalid bill day.")
            try require(b.matchingMerchant == nil || !RecurringBills.key(b.matchingMerchant!).isEmpty, "Enter a bill description for import matching.")
            try require(category(b.categoryID)?.currency == currency(b.accountID), "Bill account and category currencies must match.")
            try require(!b.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && b.amount > 0 && b.amount <= cap && accountIDs.contains(b.accountID) && categoryIDs.contains(b.categoryID), "Enter a bill name, positive amount, account, and category.")
        }
    }
    mutating func payBill(_ id: UUID, expectedDue: Date? = nil, now: Date = Date()) throws {
        guard let index = bills.firstIndex(where: { $0.id == id }) else { throw FinanceError(message: "This bill is no longer available.") }
        let bill = bills[index]
        // Guard both the saved completion and the tapped occurrence before any balance changes.
        guard !bill.isPaymentComplete(on: now), expectedDue == nil || expectedDue == bill.due else {
            throw FinanceError(message: "This payment has already been marked complete.")
        }
        var candidate = self
        candidate.bills[index].lastPaidAt = now
        candidate.transactions.append(Transaction(merchant: bill.name, amount: bill.amount, kind: .expense, date: now, accountID: bill.accountID, categoryID: bill.categoryID, note: "Recurring bill", recurringBillID: bill.id))
        // Capture the billing day for older manual reminders before a short month can clamp it.
        candidate.bills[index].anchorDay = bill.anchorDay ?? Calendar.current.component(.day, from: bill.due)
        candidate.bills[index].due = bill.frequency.next(after: bill.due, anchorDay: candidate.bills[index].anchorDay)
        try candidate.validate()
        self = candidate
    }
    static func demo(now: Date = Date()) -> FinanceData {
        var data = FinanceData()
        data.accounts = [Account(name: "TD Chequing", openingBalance: 8_000_00), Account(name: "EQ Savings", openingBalance: 42_650_00), Account(name: "Investments", openingBalance: 72_000_00)]
        data.categories = [Category(name: "Rent", symbol: "house", limit: 1_850_00), Category(name: "Groceries", symbol: "basket", limit: 900_00), Category(name: "Dining", symbol: "fork.knife", limit: 450_00), Category(name: "Transport", symbol: "tram", limit: 350_00), Category(name: "Entertainment", symbol: "play.rectangle", limit: 250_00), Category(name: "Health", symbol: "leaf", limit: 300_00)]
        // Keep rent and utilities separate without increasing the sample's total budget.
        data.categories.append(Category(name: "Utilities", symbol: "bolt", limit: 50_00))
        data.categories.append(Category(name: "Shopping", symbol: "bag", limit: 0))
        data.categories.append(Category(name: "Other", symbol: "tag", limit: 0))
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: now)!.start
        let day = calendar.component(.day, from: now)
        let rows: [(String, Int, Int, Int, Bool)] = [("Rent", 1_850_00, 0, 1, false), ("Whole Foods Market", 88_45, 1, max(1, day - 1), false), ("Blue Bottle Coffee", 7_25, 2, day, false), ("Presto Transit", 30_00, 3, day, true), ("Netflix Canada", 18_99, 4, 3, false), ("Equinox Fitness", 220_00, 5, 4, false), ("Farm Boy Organic", 64_18, 1, max(1, day - 2), false), ("Apple Store", 42_50, 7, day, true), ("Dinner with friends", 110_00, 2, max(1, day - 3), true)]
        data.transactions = rows.map { Transaction(merchant: $0.0, amount: $0.1, kind: .expense, date: calendar.date(byAdding: .day, value: $0.3 - 1, to: start)!, accountID: data.accounts[0].id, categoryID: data.categories[$0.2].id, needsReview: $0.4) }
        data.transactions.append(Transaction(merchant: "Shopify Payroll", amount: 6_450_00, kind: .income, date: start, accountID: data.accounts[0].id, categoryID: data.categories[0].id, note: "Monthly salary"))
        for (name, symbol, target, saved, months) in [("Emergency Fund", "shield", 20_000_00, 20_000_00, 1), ("First Home Down Payment", "house", 40_000_00, 15_400_00, 26), ("Japan Autumn Trip", "airplane", 7_500_00, 4_800_00, 11), ("EV Car Replacement", "car", 10_500_00, 2_450_00, 19)] {
            data.goals.append(Goal(name: name, symbol: symbol, target: target, saved: saved, accountID: data.accounts[1].id, deadline: calendar.date(byAdding: .month, value: months, to: now)!, highPriority: months < 12))
        }
        data.bills = [Bill(name: "Spotify Family", amount: 11_99, due: calendar.date(byAdding: .day, value: 1, to: now)!, accountID: data.accounts[0].id, categoryID: data.categories[4].id), Bill(name: "Hydro Electricity", amount: 84_20, due: calendar.date(byAdding: .day, value: 5, to: now)!, accountID: data.accounts[0].id, categoryID: data.categories[6].id)]
        return data
    }
}

// Locale-independent input accepts dollars and at most two fractional digits; parsing never silently rounds.
enum Money {
    static func parse(_ value: String, allowNegative: Bool = false) -> Int? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = allowNegative ? #"^-?[0-9]{1,9}(\.[0-9]{1,2})?$"# : #"^[0-9]{1,9}(\.[0-9]{1,2})?$"#
        guard value.range(of: pattern, options: .regularExpression) != nil, let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return NSDecimalNumber(decimal: number * 100).intValue
    }
    static func input(_ cents: Int) -> String { NSDecimalNumber(decimal: Decimal(cents) / 100).stringValue }
    static func format(_ cents: Int, currency: String = "CAD") -> String {
        let formatted = (Double(cents) / 100).formatted(.currency(code: currency).locale(Locale(identifier: "en_CA")))
        // Use one unambiguous ISO label for foreign amounts instead of repeating USD and US$.
        return currency == "CAD" ? formatted : (Double(cents) / 100).formatted(.currency(code: currency).presentation(.isoCode).locale(Locale(identifier: "en_CA")))
    }
}

// Explicit ISO currency evidence wins over symbols; a bare dollar sign is intentionally ambiguous.
enum Currency {
    static let supported = ["CAD", "USD", "GBP", "EUR", "AUD", "NZD", "CHF", "SGD", "HKD"]
    static func detect(_ text: String) throws -> String? {
        let pattern = #"\b(CAD|USD|GBP|EUR|AUD|NZD|CHF|SGD|HKD|JPY|KWD|BHD|CNY|INR)\b"#
        let expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let ns = text as NSString
        var codes = Set(expression.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range).uppercased() })
        if text.contains("£") { codes.insert("GBP") }
        if text.contains("€") { codes.insert("EUR") }
        if text.contains("US$") { codes.insert("USD") }
        if text.contains("CA$") || text.contains("C$") { codes.insert("CAD") }
        guard codes.count <= 1 else { throw FinanceError(message: "Multiple currencies were found. Import one currency per account and statement.") }
        guard let code = codes.first else { return nil }
        guard supported.contains(code) else { throw FinanceError(message: "\(code) is not supported yet. Supported currencies: \(supported.joined(separator: ", ")).") }
        return code
    }
}

extension FinanceData {
    // Editing or deleting one side keeps the pair balanced; account/direction changes require a new transfer.
    mutating func replaceTransaction(_ entry: Transaction) throws {
        guard let index = transactions.firstIndex(where: { $0.id == entry.id }) else { transactions.append(entry); return }
        let old = transactions[index]
        if let pair = old.transferPairID {
            guard entry.accountID == old.accountID, entry.kind == old.kind,
                  let peer = transactions.firstIndex(where: { $0.transferPairID == pair && $0.id != old.id }) else { throw FinanceError(message: "Keep the linked transfer accounts and direction unchanged.") }
            transactions[peer].amount = entry.amount; transactions[peer].date = entry.date
        }
        // Ordinary editors must not erase capture provenance when rebuilding a transaction value.
        var replacement = entry
        replacement.captureSource = old.captureSource ?? entry.captureSource
        replacement.originalApplePayCapture = old.originalApplePayCapture ?? entry.originalApplePayCapture
        replacement.statementConfirmed = old.statementConfirmed ?? entry.statementConfirmed
        transactions[index] = replacement
    }
    mutating func deleteTransaction(_ id: UUID) {
        let pair = transactions.first(where: { $0.id == id })?.transferPairID
        transactions.removeAll { $0.id == id || (pair != nil && $0.transferPairID == pair) }
    }
}

extension FinanceData {
    var savingsCandidates: [Transaction] {
        transactions.filter { !$0.isTransfer && $0.kind == .expense && Self.isSavingsDescription($0.merchant) }.sorted { $0.date < $1.date }
    }
    static func isSavingsDescription(_ text: String) -> Bool {
        text.range(of: #"(?i)\b(transfer to savings|to savings account)\b"#, options: .regularExpression) != nil
    }
    // Shared by new imports and the explicit review action for history imported before savings support.
    mutating func linkSavingsTransfer(_ id: UUID, savingsAccountID: UUID? = nil) throws {
        guard let sourceIndex = transactions.firstIndex(where: { $0.id == id }), !transactions[sourceIndex].isTransfer else { return }
        let entry = transactions[sourceIndex]
        guard entry.kind == .expense else { throw FinanceError(message: "A savings transfer must be an outgoing withdrawal.") }
        let destination = entry.accountID, code = currency(entry.accountID), reference = RecurringBills.key(entry.merchant)
        let savings: Account
        if let savingsAccountID {
            guard let existing = accounts.first(where: { $0.id == savingsAccountID }), existing.id != destination, existing.currency == code else { throw FinanceError(message: "Choose a different savings account in the same currency.") }
            savings = existing
        } else if let existing = accounts.first(where: { $0.savingsSourceAccountID == destination && $0.savingsReference == reference }) { savings = existing }
        else {
            savings = Account(name: accountName(destination) + " Savings", openingBalance: 0, currencyCode: code == "CAD" ? nil : code, savingsSourceAccountID: destination, savingsReference: reference)
            accounts.append(savings)
        }
        let credits = transactions.indices.filter { index in
            let t = transactions[index]
            return t.accountID == savings.id && !t.isTransfer && t.kind == .income && t.amount == entry.amount && t.date == entry.date && t.merchant.lowercased().contains("transfer")
        }
        guard credits.count <= 1 else { throw FinanceError(message: "Several destination credits match this savings transfer. Review them before attaching savings.") }
        let pair = UUID()
        transactions[sourceIndex].transferAccountID = savings.id; transactions[sourceIndex].transferPairID = pair
        transactions[sourceIndex].recurringBillID = nil
        if let index = credits.first {
            transactions[index].transferAccountID = destination; transactions[index].transferPairID = pair
        } else {
            transactions.append(Transaction(merchant: "Transfer from " + accountName(destination), amount: entry.amount, kind: .income, date: entry.date, accountID: savings.id, categoryID: entry.categoryID, note: "Tracked from an imported savings transfer; this is not the bank's complete savings balance.", needsReview: true, transferAccountID: destination, transferPairID: pair, derivedTransfer: true))
        }
    }
    mutating func trackExistingSavingsTransfers(_ ids: Set<UUID>) throws {
        var candidate = self
        candidate.version = max(candidate.version, 2)
        let eligible = Set(savingsCandidates.map(\.id))
        guard ids.isSubset(of: eligible) else { throw FinanceError(message: "Savings candidates changed. Review them again before attaching.") }
        for id in ids { try candidate.linkSavingsTransfer(id) }
        try candidate.validate()
        self = candidate
    }
}

// Calendar-week buckets are clipped to the selected month, so their sum matches its reports.
// Integer cents, reporting-currency filtering and transfer exclusion share ledger semantics.
struct SpendingWeek: Identifiable {
    var start: Date
    var days: [Date]
    var entries: [Transaction]
    var id: Date { start }
    var total: Int { entries.reduce(0) { $0 + $1.amount } }
    func entries(on day: Date, calendar: Calendar = .current) -> [Transaction] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }
    static func calculate(data: FinanceData, month: Date, calendar: Calendar = .current) -> [SpendingWeek] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let expenses = data.reportingEntries(in: month).filter { $0.kind == .expense }
        var result: [SpendingWeek] = []
        var day = interval.start
        while day < interval.end {
            let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
            if result.last?.start != start { result.append(SpendingWeek(start: start, days: [], entries: [])) }
            result[result.count - 1].days.append(day)
            result[result.count - 1].entries += expenses.filter { calendar.isDate($0.date, inSameDayAs: day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return result
    }
}

// A read-only monthly plan keeps estimates out of saved manual limits and portable ledger records.
struct AutomaticBudgets: Equatable {
    var limits: [UUID: Int] = [:]
    var historyMonths: [String: Int] = [:]

    static func calculate(data: FinanceData, month: Date, now: Date = Date(), calendar: Calendar = .current) -> AutomaticBudgets {
        let selected = calendar.dateInterval(of: .month, for: month)!.start
        let current = calendar.dateInterval(of: .month, for: now)!.start
        // Future selections use only completed history available today; historical views never look ahead.
        let end = min(selected, current)
        let start = calendar.date(byAdding: .month, value: -3, to: end)!
        let accounts = Dictionary(uniqueKeysWithValues: data.accounts.map { ($0.id, $0.currency) })
        var observed: [String: Set<Date>] = [:]
        var spending: [UUID: Int] = [:]
        // Bucket once for the whole ledger instead of rescanning every category on every screen.
        for entry in data.transactions where !entry.isTransfer && entry.date >= start && entry.date < end {
            guard let currency = accounts[entry.accountID] else { continue }
            let recordedMonth = calendar.dateInterval(of: .month, for: entry.date)!.start
            observed[currency, default: []].insert(recordedMonth)
            if entry.kind == .expense { spending[entry.categoryID, default: 0] += entry.amount }
        }
        var result = AutomaticBudgets(historyMonths: observed.mapValues(\.count))
        for category in data.categories {
            if category.usesAutomaticBudget {
                let count = result.historyMonths[category.currency, default: 0]
                let total = spending[category.id, default: 0]
                // Missing category spending in an observed month counts as zero; wholly missing months are skipped.
                // Round the integer-cent mean to the nearest cent without floating-point financial arithmetic.
                result.limits[category.id] = count > 0 ? (total + count / 2) / count : 0
            } else { result.limits[category.id] = category.limit }
        }
        return result
    }

    func resolved(_ category: Category) -> Category {
        var copy = category
        // Resolve the mode before filling a virtual limit, so an automatic amount never becomes manual by accident.
        copy.automaticBudget = category.usesAutomaticBudget
        copy.limit = limits[category.id] ?? category.limit
        return copy
    }

    func note(for category: Category) -> String {
        guard category.usesAutomaticBudget else { return "Manual monthly limit" }
        let count = historyMonths[category.currency, default: 0]
        guard count > 0 else { return "Automatic · Needs prior-month history" }
        return "Automatic · Average of \(count) prior month\(count == 1 ? "" : "s")"
    }
}
