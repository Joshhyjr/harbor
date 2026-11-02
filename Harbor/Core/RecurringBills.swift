import Foundation

// Recognise explicit service descriptions, never generic Apple/Amazon store or processor charges.
enum SubscriptionServices {
    static func name(_ merchant: String) -> String? {
        let value = " " + RecurringBills.key(merchant) + " "
        let services: [(String, [String])] = [
            ("Apple iCloud", ["icloud", "i cloud"]), ("Apple Music", ["apple music"]),
            ("Apple TV+", ["apple tv plus", "apple tv subscription"]), ("Apple One", ["apple one"]),
            ("Netflix", ["netflix"]), ("Spotify", ["spotify"]), ("YouTube Premium", ["youtube premium"]),
            ("Disney+", ["disney plus", "disneyplus"]), ("Crave", ["crave"]),
            ("Prime Video", ["prime video"]), ("Audible", ["audible"])
        ]
        return services.first { _, aliases in aliases.contains { value.contains(" " + $0 + " ") } }?.0
    }
}

// Calendar-based cadence handles short months and preserves the original billing day.
enum BillFrequency: String, Codable, CaseIterable {
    case weekly, fortnightly, monthly, quarterly, annually
    var label: String { rawValue.capitalized }
    var tolerance: Int { self == .weekly || self == .fortnightly ? 2 : 5 }
    func next(after date: Date, anchorDay: Int? = nil, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly, .fortnightly:
            return calendar.date(byAdding: .day, value: self == .weekly ? 7 : 14, to: date)!
        case .monthly, .quarterly, .annually:
            let months = self == .monthly ? 1 : self == .quarterly ? 3 : 12
            let next = calendar.date(byAdding: .month, value: months, to: date)!
            let day = min(anchorDay ?? calendar.component(.day, from: date), calendar.range(of: .day, in: .month, for: next)!.count)
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: next)
            components.day = day
            return calendar.date(from: components)!
        }
    }
}
struct RecurringSuggestion: Identifiable {
    let payments: [Transaction]
    let frequency: BillFrequency
    var latest: Transaction { payments.last! }
    var id: String { RecurringBills.identity(latest.accountID, latest.merchant) }
    var minimum: Int { payments.map(\.amount).min()! }
    var maximum: Int { payments.map(\.amount).max()! }
    var due: Date { frequency.next(after: latest.date) }
}
enum RecurringBills {
    static func merchantKey(_ name: String) -> String { key(SubscriptionServices.name(name) ?? name) }
    static func identity(_ account: UUID, _ merchant: String) -> String { account.uuidString + ":" + merchantKey(merchant) }
    // Conservative normalization keeps account numbers and meaningful merchant words intact.
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    // Classification may use Apple suggestions; cadence and amounts always come from recorded payments.
    static func autoTrack(in data: inout FinanceData, now: Date = Date()) throws {
        var next = data
        for index in next.transactions.indices {
            let entry = next.transactions[index]
            guard entry.kind == .expense, !entry.isTransfer, entry.date <= now,
                  entry.categoryManuallySet != true, entry.needsReview || entry.automaticallyReviewed == true,
                  SubscriptionServices.name(entry.merchant) != nil else { continue }
            let row = ImportRow(date: entry.date, merchant: entry.merchant, amount: entry.amount, kind: entry.kind, category: next.category(entry.categoryID)?.name ?? "Other", note: entry.note)
            guard !Categorization.hasTransferAmbiguity(row),
                  Categorization.local(row, in: data, accountID: entry.accountID, currency: data.currency(entry.accountID))?.reason == "Recognised subscription service" else { continue }
            let currency = next.currency(entry.accountID)
            let category = Categorization.existing("Subscription", in: next, currency: currency)
                ?? Category(name: "Subscription", symbol: "repeat", limit: 0, importKey: "subscription", currencyCode: currency)
            if !next.categories.contains(where: { $0.id == category.id }) { next.categories.append(category) }
            next.transactions[index].categoryID = category.id
            next.transactions[index].needsReview = false
            next.transactions[index].automaticallyReviewed = true
        }
        // Three clear, stable payments in a recurring category are sufficient without another approval.
        for suggestion in suggestions(in: next, now: now, includingTracked: true) {
            let latest = suggestion.latest
            let category = next.category(latest.categoryID)
            let categoryKey = category?.importKey ?? CategoryCatalog.key(category?.name ?? "")
            guard ["rent", "utilities", "insurance", "subscription"].contains(categoryKey),
                  suggestion.payments.allSatisfy({ !$0.needsReview && $0.categoryID == latest.categoryID }),
                  suggestion.maximum <= suggestion.minimum + suggestion.minimum / 5 else { continue }
            let existing = next.bills.firstIndex { identity($0.accountID, $0.matchingMerchant ?? $0.name) == suggestion.id }
            // User-created/edited bills are authoritative; only an estimated detected schedule can be refined.
            if let existing, !(next.bills[existing].automaticallyDetected == true && next.bills[existing].needsScheduleReview == true) { continue }
            guard existing != nil || next.bills.count < 500 else { continue }
            let bill = Bill(id: existing.map { next.bills[$0].id } ?? UUID(), name: SubscriptionServices.name(latest.merchant) ?? latest.merchant,
                            amount: latest.amount, due: suggestion.due, accountID: latest.accountID, categoryID: latest.categoryID,
                            recurrence: suggestion.frequency, matchingMerchant: merchantKey(latest.merchant), minimumAmount: suggestion.minimum,
                            maximumAmount: suggestion.maximum, anchorDay: Calendar.current.component(.day, from: latest.date),
                            automaticallyDetected: true, needsScheduleReview: false)
            if let existing { next.bills[existing] = bill } else { next.bills.append(bill) }
            let ids = Set(suggestion.payments.map(\.id))
            for index in next.transactions.indices where ids.contains(next.transactions[index].id) { next.transactions[index].recurringBillID = bill.id }
        }
        // A named subscription is a bill even with one payment, but its unseen cadence needs a focused prompt.
        let subscriptions = Dictionary(grouping: next.transactions.filter {
            $0.kind == .expense && !$0.isTransfer && !$0.needsReview && $0.date <= now
                && SubscriptionServices.name($0.merchant) != nil
                && (next.category($0.categoryID)?.importKey ?? CategoryCatalog.key(next.category($0.categoryID)?.name ?? "")) == "subscription"
        }) { identity($0.accountID, $0.merchant) }
        for id in subscriptions.keys.sorted() {
            guard let latest = subscriptions[id]?.max(by: { $0.date < $1.date }),
                  !(next.ignoredRecurringMerchants ?? []).contains(id), next.bills.count < 500,
                  !next.bills.contains(where: { identity($0.accountID, $0.matchingMerchant ?? $0.name) == id }) else { continue }
            let bill = Bill(name: SubscriptionServices.name(latest.merchant)!, amount: latest.amount,
                            due: BillFrequency.monthly.next(after: latest.date), accountID: latest.accountID, categoryID: latest.categoryID,
                            recurrence: .monthly, matchingMerchant: merchantKey(latest.merchant), minimumAmount: latest.amount, maximumAmount: latest.amount,
                            anchorDay: Calendar.current.component(.day, from: latest.date), automaticallyDetected: true, needsScheduleReview: true)
            next.bills.append(bill)
            if let index = next.transactions.firstIndex(where: { $0.id == latest.id }) { next.transactions[index].recurringBillID = bill.id }
        }
        try next.validate()
        data = next
    }
    static func dismiss(_ bill: Bill, in data: inout FinanceData) {
        // A deliberate deletion also suppresses rediscovery; existing spending is never deleted.
        let id = identity(bill.accountID, bill.matchingMerchant ?? bill.name)
        data.ignoredRecurringMerchants = Array(Set((data.ignoredRecurringMerchants ?? []) + [id])).sorted()
        data.bills.removeAll { $0.id == bill.id }
        for index in data.transactions.indices where data.transactions[index].recurringBillID == bill.id { data.transactions[index].recurringBillID = nil }
    }
    static func suggestions(in data: FinanceData, now: Date = Date(), calendar: Calendar = .current, includingTracked: Bool = false) -> [RecurringSuggestion] {
        let groups = Dictionary(grouping: data.transactions.filter { $0.kind == .expense && !$0.isTransfer && $0.date <= now }) {
            identity($0.accountID, $0.merchant)
        }
        return groups.values.compactMap { entries -> RecurringSuggestion? in
            let sorted = entries.sorted { $0.date < $1.date }
            guard sorted.count >= 3, let latest = sorted.last, !key(latest.merchant).isEmpty,
                  !(data.ignoredRecurringMerchants ?? []).contains(identity(latest.accountID, latest.merchant)),
                  includingTracked || !data.bills.contains(where: { $0.accountID == latest.accountID && merchantKey($0.matchingMerchant ?? $0.name) == merchantKey(latest.merchant) }) else { return nil }
            // Use the latest six payments; same-day duplicates or irregular shopping fail the cadence check.
            let payments = Array(sorted.suffix(6))
            let amounts = payments.map(\.amount).sorted()
            let median = amounts[amounts.count / 2]
            guard amounts.first! >= median / 2, amounts.last! <= median + median / 2 else { return nil }
            for frequency in BillFrequency.allCases {
                let anchor = calendar.component(.day, from: payments[0].date)
                let regular = zip(payments, payments.dropFirst()).allSatisfy { previous, next in
                    let expected = frequency.next(after: previous.date, anchorDay: anchor, calendar: calendar)
                    let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: expected), to: calendar.startOfDay(for: next.date)).day!
                    return abs(gap) <= frequency.tolerance
                }
                if regular { return RecurringSuggestion(payments: payments, frequency: frequency) }
            }
            return nil
        }.sorted { $0.id < $1.id }
    }
    static func confirm(_ suggestion: RecurringSuggestion, in data: inout FinanceData) throws {
        // Recompute evidence at confirmation so stale suggestions cannot create duplicate bills.
        guard let current = suggestions(in: data).first(where: { $0.id == suggestion.id }) else {
            throw FinanceError(message: "This bill suggestion changed. Review the latest payments.")
        }
        let latest = current.latest
        let bill = Bill(name: latest.merchant, amount: latest.amount, due: current.due, accountID: latest.accountID,
                        categoryID: latest.categoryID, recurrence: current.frequency, matchingMerchant: merchantKey(latest.merchant),
                        minimumAmount: current.minimum, maximumAmount: current.maximum,
                        anchorDay: Calendar.current.component(.day, from: latest.date))
        var candidate = data
        candidate.bills.append(bill)
        let ids = Set(current.payments.map(\.id))
        for index in candidate.transactions.indices where ids.contains(candidate.transactions[index].id) {
            candidate.transactions[index].recurringBillID = bill.id
        }
        try candidate.validate()
        data = candidate
    }
    static func matchImports(_ importedIDs: Set<UUID>, in data: inout FinanceData, now: Date = Date(), calendar: Calendar = .current) {
        // Only newly appended expenses may settle a confirmed reminder; matching never creates spending.
        let indices = data.transactions.indices.filter { importedIDs.contains(data.transactions[$0].id) }
            .sorted { data.transactions[$0].date < data.transactions[$1].date }
        for index in indices {
            let payment = data.transactions[index]
            guard payment.kind == .expense, !payment.isTransfer, payment.date <= now, payment.recurringBillID == nil else { continue }
            let matches = data.bills.indices.filter { billIndex in
                let bill = data.bills[billIndex]
                guard bill.needsScheduleReview != true, let merchant = bill.matchingMerchant, merchantKey(merchant) == merchantKey(payment.merchant), bill.accountID == payment.accountID else { return false }
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: bill.due), to: calendar.startOfDay(for: payment.date)).day!
                let low = bill.minimumAmount ?? bill.amount, high = bill.maximumAmount ?? bill.amount
                return abs(days) <= bill.frequency.tolerance && payment.amount >= low - low / 5 && payment.amount <= high + high / 5
            }
            // A changed detected bill becomes a focused prompt rather than silently accepting the new terms.
            guard matches.count == 1, let billIndex = matches.first else {
                for billIndex in data.bills.indices {
                    let bill = data.bills[billIndex]
                    guard bill.automaticallyDetected == true, bill.needsScheduleReview != true,
                          bill.accountID == payment.accountID, merchantKey(bill.matchingMerchant ?? bill.name) == merchantKey(payment.merchant) else { continue }
                    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: bill.due), to: calendar.startOfDay(for: payment.date)).day!
                    // Earlier historical backfills do not change the next expected occurrence.
                    guard days >= -bill.frequency.tolerance else { continue }
                    data.bills[billIndex].needsScheduleReview = true
                    data.bills[billIndex].detectionReviewReason = "A new payment differs from the expected date or amount. Check the billing schedule and amount."
                }
                continue
            }
            data.transactions[index].recurringBillID = data.bills[billIndex].id
            data.bills[billIndex].amount = payment.amount
            let bill = data.bills[billIndex]
            data.bills[billIndex].due = bill.frequency.next(after: bill.due, anchorDay: bill.anchorDay, calendar: calendar)
        }
    }
}

// Cleanup is explicitly requested in Settings; no category migration runs silently on load.
extension FinanceData {
    static func simpleCategory(_ name: String) -> String {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "housing & utilities": return "Utilities"
        case "dining & cafes": return "Dining"
        case "personal & wellness": return "Health"
        case "entertainment & subscriptions": return "Entertainment"
        case "uncategorized": return "Other"
        default: return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    // Derive availability from the saved ledger, so relaunch/restore needs no separate completion flag.
    // Comparing the validated result also detects duplicate merges and explicit Rent reclassification.
    var needsCategorySimplification: Bool {
        var candidate = self
        do {
            try candidate.simplifyCategories()
            return candidate != self
        } catch { return false }
    }
    mutating func simplifyCategories() throws {
        var candidate = self
        for category in categories {
            guard let index = candidate.categories.firstIndex(where: { $0.id == category.id }) else { continue }
            let name = Self.simpleCategory(category.name)
            if let target = candidate.categories.first(where: { $0.id != category.id && $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.currency == category.currency }) {
                let targetIndex = candidate.categories.firstIndex(where: { $0.id == target.id })!
                // Combining limits preserves the total budget instead of silently discarding an override.
                candidate.categories[targetIndex].limit += category.limit
                for i in candidate.transactions.indices where candidate.transactions[i].categoryID == category.id { candidate.transactions[i].categoryID = target.id }
                for i in candidate.bills.indices where candidate.bills[i].categoryID == category.id { candidate.bills[i].categoryID = target.id }
                candidate.categories.remove(at: index)
            } else { candidate.categories[index].name = name }
        }
        // Only explicit Rent descriptions move automatically; ambiguous housing expenses remain in Utilities.
        for utilities in candidate.categories.filter({ $0.name.caseInsensitiveCompare("Utilities") == .orderedSame }) {
            let rent = candidate.categories.first(where: { $0.name.caseInsensitiveCompare("Rent") == .orderedSame && $0.currency == utilities.currency }) ?? Category(name: "Rent", symbol: "house", limit: 0, currencyCode: utilities.currencyCode)
            if !candidate.categories.contains(where: { $0.id == rent.id }) { candidate.categories.append(rent) }
            for i in candidate.transactions.indices where candidate.transactions[i].categoryID == utilities.id && RecurringBills.key(candidate.transactions[i].merchant) == "rent" { candidate.transactions[i].categoryID = rent.id }
            for i in candidate.bills.indices where candidate.bills[i].categoryID == utilities.id && RecurringBills.key(candidate.bills[i].name) == "rent" { candidate.bills[i].categoryID = rent.id }
        }
        try candidate.validate()
        self = candidate
    }
}
