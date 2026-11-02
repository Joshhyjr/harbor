import SwiftUI

struct EditorForm<Content: View>: View {
    @EnvironmentObject var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    let title: String
    let save: () -> Bool
    @ViewBuilder var content: Content
    var body: some View {
        NavigationStack {
            Form { content; if let error = store.error { Section { Text(error).foregroundStyle(.red) } } }
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { store.error = nil; dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if save() { dismiss() } }.bold() }
                }
        }.tint(HarborStyle.blue)
    }
}
struct TransactionEditor: View {
    @EnvironmentObject var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    var existing: Transaction?
    @State private var merchant = ""
    @State private var amount = ""
    @State private var kind = TransactionKind.expense
    @State private var date = Date()
    @State private var account: UUID?
    @State private var category: UUID?
    @State private var note = ""
    @State private var needsReview = false
    @State private var delete = false
    @State private var proposing = false
    @State private var proposedCategory: Category?
    @State private var categoryMessage: String?
    @State private var categoryTask: Task<Void, Never>?
    @State private var newCategoryName = ""
    var body: some View {
        EditorForm(title: existing == nil ? "Add Transaction" : "Edit Transaction", save: save) {
            Section("Details") {
                TextField("Merchant or source", text: $merchant).accessibilityIdentifier("transaction.merchant")
                TextField("Amount (\(account.map { store.data.currency($0) } ?? store.data.reportingCurrency))", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("transaction.amount")
                Picker("Type", selection: $kind) { ForEach(TransactionKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Account", selection: $account) { Text("Choose account").tag(nil as UUID?); ForEach(store.data.accounts) { Text("\($0.name) · \($0.currency)").tag(Optional($0.id)) } }
                Picker("Category", selection: $category) { Text("Choose category").tag(nil as UUID?); ForEach(store.data.categories.filter { $0.currency == (account.map { store.data.currency($0) } ?? store.data.reportingCurrency) } + (proposedCategory.map { [$0] } ?? []).filter { $0.currency == (account.map { store.data.currency($0) } ?? store.data.reportingCurrency) }) { Text($0.name).tag(Optional($0.id)) } }
                // A manual name overrides the picker/model and is saved only together with this transaction.
                TextField("New category name (optional)", text: $newCategoryName).accessibilityIdentifier("transaction.newCategory")
                Text("Use a suggestion, choose a saved category, or enter your own name. A new category is created only when you save this transaction.").font(.caption).foregroundStyle(.secondary)
                // Suggest only on request in manual forms; the category picker remains authoritative.
                Button("Suggest category") { suggestCategory() }.disabled(proposing || merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || account == nil || existing?.isTransfer == true)
                if proposing { ProgressView("Checking on this device…") }
                if let categoryMessage { Text(categoryMessage).font(.caption).foregroundStyle(.secondary) }
                TextField("Note", text: $note, axis: .vertical)
                Toggle("Needs review", isOn: $needsReview)
            }
            // Original tap details remain inspectable even after statement confirmation or manual edits.
            if let original = existing?.originalApplePayCapture {
                Section("Apple Pay capture") {
                    Text(existing?.statementConfirmed == true ? "Confirmed against an imported statement" : "Awaiting statement confirmation")
                    Text("Original: \(original.merchant) · \(store.format(original.amount, currency: original.currency))")
                    Text(original.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                }
            }
            if existing?.isTransfer == true { Text("Linked savings transfer. Amount and date changes update both accounts; deleting it removes both entries. Account and direction must stay unchanged.").font(.caption) }
            if existing != nil { Section { Button("Delete transaction", role: .destructive) { delete = true } } }
            if store.data.accounts.isEmpty { Text("Create an account before adding a transaction.").foregroundStyle(.secondary) }
        }
        .onAppear {
            if let entry = existing { merchant = entry.merchant; amount = Money.input(entry.amount); kind = entry.kind; date = entry.date; account = entry.accountID; category = entry.categoryID; note = entry.note; needsReview = entry.needsReview }
            else { account = store.data.accounts.first?.id; category = store.data.categories.first?.id }
        }
        .onChange(of: account) { _, account in
            // A proposal belongs to the selected currency, just like any saved category.
            let currency = account.map { store.data.currency($0) } ?? store.data.reportingCurrency
            if let proposedCategory, proposedCategory.currency != currency { self.proposedCategory = nil; categoryMessage = nil }
            if let category, (store.data.category(category) ?? proposedCategory)?.currency != currency { self.category = nil }
        }
        .onDisappear { categoryTask?.cancel() }
        .confirmationDialog(existing?.isTransfer == true ? "Delete both linked transfer entries permanently?" : "Delete this transaction permanently?", isPresented: $delete, titleVisibility: .visible) { Button("Delete", role: .destructive) { if store.update({ if let id = existing?.id { $0.deleteTransaction(id) } }) { dismiss() } } }
    }
    private func suggestCategory() {
        guard let account else { return }
        let originalMerchant = merchant, originalKind = kind
        let originalCategory = category
        let snapshot = store.data
        let row = ImportRow(date: date, merchant: merchant, amount: Money.parse(amount) ?? 1, kind: kind, category: "Other", note: "")
        proposing = true
        categoryTask = Task {
            defer { proposing = false }
            do {
                let rows = try await Categorization.prepare([row], in: snapshot, accountID: account, currency: snapshot.currency(account))
                try Task.checkCancellation()
                guard originalMerchant == merchant, originalKind == kind, self.account == account, category == originalCategory, store.data == snapshot else { return }
                guard let suggestion = rows.first, let reason = suggestion.categoryReason else { categoryMessage = "No clear suggestion. Choose a category yourself. " + AppleCategoryModel.status; return }
                if let id = suggestion.suggestedCategoryID { category = id; proposedCategory = nil }
                else {
                    let newCategory = Category(name: suggestion.category, symbol: CategoryCatalog.symbol(suggestion.category), limit: 0, importKey: CategoryCatalog.key(suggestion.category), currencyCode: snapshot.currency(account))
                    proposedCategory = newCategory; category = newCategory.id
                }
                categoryMessage = "Suggested: " + suggestion.category + " · " + reason + ". You can change the picker before saving."
            } catch is CancellationError { }
            catch { categoryMessage = "Choose a category manually." }
        }
    }
    private func save() -> Bool {
        guard let cents = Money.parse(amount), let account else { store.error = "Enter a valid amount with at most two decimal places and an account."; return false }
        // Resolve draft choices locally; cancellation and failed saves never add unused category records.
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen: Category?
        if !name.isEmpty {
            chosen = Categorization.existing(name, in: store.data, currency: store.data.currency(account))
                ?? Category(name: name, symbol: CategoryCatalog.symbol(name), limit: 0, importKey: CategoryCatalog.key(name), currencyCode: store.data.currency(account))
        } else {
            chosen = category.flatMap { id in store.data.category(id) ?? (proposedCategory?.id == id ? proposedCategory : nil) }
        }
        guard let chosen else { store.error = "Choose a category, request a suggestion, or enter your own category name."; return false }
        // Corrections retain the payment link created by recurring import matching.
        guard existing == nil || store.data.currency(existing!.accountID) == store.data.currency(account) else { store.error = "Choose an account in the original currency."; return false }
        let entry = Transaction(id: existing?.id ?? UUID(), merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), amount: cents, kind: kind, date: date, accountID: account, categoryID: chosen.id, note: note, needsReview: needsReview, recurringBillID: existing?.recurringBillID, transferAccountID: existing?.transferAccountID, transferPairID: existing?.transferPairID, derivedTransfer: existing?.derivedTransfer, categoryManuallySet: true)
        return store.update { data in
            // A suggested new category is committed with the transaction, never when the form is cancelled.
            if !data.categories.contains(where: { $0.id == chosen.id }) { data.categories.append(chosen) }
            try data.replaceTransaction(entry)
        }
    }
}
struct CategoryEditor: View {
    @EnvironmentObject var store: HarborStore
    var existing: Category?
    // Category browsing puts names/icons first; Budget retains its existing limit-first editor.
    var categoryFirst = false
    var onSaved: (() -> Void)? = nil
    @State private var name = ""
    @State private var limit = ""
    @State private var symbol = "basket"
    @State private var automatic = true
    private var automaticPlan: AutomaticBudgets {
        // Preview switching a manual category to automatic before saving the user's choice.
        var candidate = store.data
        if let id = existing?.id, let index = candidate.categories.firstIndex(where: { $0.id == id }) {
            candidate.categories[index].automaticBudget = true
        }
        return AutomaticBudgets.calculate(data: candidate, month: store.month)
    }
    private var automaticCategory: Category? {
        guard var category = existing else { return nil }
        category.automaticBudget = true
        return automaticPlan.resolved(category)
    }
    var body: some View {
        EditorForm(title: existing == nil ? "New Category" : categoryFirst ? "Edit Category" : "Edit Budget", save: save) {
            if categoryFirst {
                Section("Make it yours") {
                    TextField("Category name", text: $name)
                    SymbolPicker(symbol: $symbol)
                }
                Section {
                    // Keep optional planning controls tucked away without changing their saved values.
                    DisclosureGroup("Monthly budget (optional)") { budgetFields }
                }
            } else {
                Section("Monthly budget") {
                    TextField("Category name", text: $name)
                    budgetFields
                    SymbolPicker(symbol: $symbol)
                }
            }
        }.onAppear {
            if let c = existing {
                name = c.name; limit = Money.input(store.budgetCategory(c).limit); symbol = c.symbol
                automatic = c.usesAutomaticBudget
            } else { limit = "0" }
        }
    }
    @ViewBuilder private var budgetFields: some View {
        Toggle("Automatic budget", isOn: $automatic).accessibilityIdentifier("category.automaticBudget")
        if automatic {
            if let category = automaticCategory {
                Text("Estimated limit: \(store.format(category.limit, currency: category.currency))").accessibilityIdentifier("category.estimatedLimit")
                Text(automaticPlan.note(for: category)).font(.caption).foregroundStyle(.secondary)
            }
            Text("Uses average spending in the previous three completed calendar months with recorded activity in this currency. Updates when history changes. Current-month spending is excluded. Incomplete records can understate the estimate.").font(.caption)
        } else {
            TextField("Limit (\(existing?.currency ?? store.data.reportingCurrency))", text: $limit).keyboardType(.decimalPad)
            Text("Set zero for no budget. Manual limits repeat each month and override automatic estimates.").font(.caption)
        }
    }
    // Retain import identity on renames; explicit mode distinguishes automatic limits from manual zero.
    private func save() -> Bool {
        // Store only the choice for automatic budgets; the selected month's estimate stays derived.
        guard let cents = automatic ? 0 : Money.parse(limit) else { store.error = "Enter a nonnegative budget with at most two decimal places."; return false }
        // Duplicate display names should be merged explicitly, preserving their references and budgets.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !store.data.categories.contains(where: { $0.id != existing?.id && $0.currency == (existing?.currency ?? store.data.reportingCurrency) && CategoryCatalog.normalized($0.name) == CategoryCatalog.normalized(trimmed) }) else {
            store.error = "That category already exists. Use Manage categories to merge them."; return false
        }
        let category = Category(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), symbol: symbol, limit: cents, importKey: existing?.importKey ?? CategoryCatalog.key(existing?.name ?? name), importAliases: existing?.importAliases, currencyCode: existing?.currency ?? store.data.reportingCurrency, automaticBudget: automatic)
        let saved = store.update { data in if let i = data.categories.firstIndex(where: { $0.id == category.id }) { data.categories[i] = category } else { data.categories.append(category) } }
        // Let a browsing screen reveal a newly saved category only after persistence succeeds.
        if saved { onSaved?() }
        return saved
    }
}
// Icon selection edits only the parent's draft; cancelling the category or goal still discards it.
struct SymbolPicker: View {
    @Binding var symbol: String
    var body: some View {
        NavigationLink { IconSelectionScreen(symbol: $symbol) } label: {
            HStack {
                Text("Icon")
                Spacer()
                IconTile(symbol: symbol).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }.accessibilityIdentifier("icon.picker").accessibilityValue(symbol)
    }
}

private struct IconSelectionScreen: View {
    @Binding var symbol: String
    @Environment(\.dismiss) private var dismiss
    @State private var emoji = ""
    private let symbols = ["house", "basket", "fork.knife", "tram", "play.rectangle", "leaf", "shield", "airplane", "car", "graduationcap", "star", "creditcard", "tag", "bag", "bolt", "gift", "pawprint", "heart", "book", "music.note", "gamecontroller", "cup.and.saucer", "figure.walk", "dumbbell", "cross.case", "wifi", "phone", "building.2"]
    private var selectedEmoji: String? { HarborIcon.emoji(in: emoji) }
    var body: some View {
        List {
            Section("Your own emoji") {
                HStack(spacing: 12) {
                    IconTile(symbol: selectedEmoji ?? symbol).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    TextField("Type or paste one emoji", text: $emoji)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("icon.emoji")
                }
                Text("Use the emoji keyboard or paste a single emoji. It will appear inside Harbor’s icon tile.")
                    .font(.caption).foregroundStyle(.secondary)
                if !emoji.isEmpty && selectedEmoji == nil {
                    Text("Choose one emoji, such as 🐾 or 🏡.").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("icon.validation")
                }
                Button("Use emoji") {
                    // Multi-scalar families, flags and skin tones are saved as one complete character.
                    guard let selectedEmoji else { return }
                    symbol = selectedEmoji
                    dismiss()
                }.disabled(selectedEmoji == nil).accessibilityIdentifier("icon.useEmoji")
            }
            Section("Harbor icons") {
                // Keep a previously saved symbol visible even if it is outside today's curated list.
                ForEach((HarborIcon.emoji(in: symbol) == nil && !symbols.contains(symbol) ? [symbol] : []) + symbols, id: \.self) { value in
                    Button {
                        symbol = value
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(symbol: value).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            Text(value.replacingOccurrences(of: ".", with: " ").capitalized).foregroundStyle(HarborStyle.navy)
                            Spacer()
                            if symbol == value { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("icon.symbol." + value)
                }
            }
        }.navigationTitle("Choose Icon").navigationBarTitleDisplayMode(.inline)
            .onAppear { emoji = HarborIcon.emoji(in: symbol) ?? "" }
    }
}
struct GoalEditor: View {
    @EnvironmentObject var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    var existing: Goal?
    @State private var name = ""
    @State private var target = ""
    @State private var saved = "0"
    @State private var symbol = "shield"
    @State private var account: UUID?
    @State private var deadline = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
    @State private var priority = false
    @State private var delete = false
    var body: some View {
        EditorForm(title: existing == nil ? "New Goal" : "Edit Goal", save: save) {
            Section("Goal") { TextField("Goal name", text: $name); SymbolPicker(symbol: $symbol); TextField("Target (\(account.map { store.data.currency($0) } ?? store.data.reportingCurrency))", text: $target).keyboardType(.decimalPad); DatePicker("Target date", selection: $deadline, displayedComponents: .date); Toggle("High priority", isOn: $priority) }
            Section("Funding") {
                Picker("Funding account", selection: $account) { Text("Choose account").tag(nil as UUID?); ForEach(store.data.accounts) { Text("\($0.name) · \($0.currency)").tag(Optional($0.id)) } }
                TextField("Total allocated (\(account.map { store.data.currency($0) } ?? store.data.reportingCurrency))", text: $saved).keyboardType(.decimalPad)
                if let account { Text("Available for this goal: \(store.format(max(0, store.data.balance(account) - store.data.allocated(account, excluding: existing?.id)), currency: store.data.currency(account)))").font(.caption) }
                Text("Set the total amount reserved, not an additional deposit. Reducing it releases funds back to the account's available balance.").font(.caption)
            }
            if existing != nil { Button("Delete goal and release funds", role: .destructive) { delete = true } }
        }.onAppear {
            if let g = existing { name = g.name; target = Money.input(g.target); saved = Money.input(g.saved); symbol = g.symbol; account = g.accountID; deadline = g.deadline; priority = g.highPriority } else { account = store.data.accounts.first?.id }
        }.confirmationDialog("Delete this goal? Its funds remain in the account.", isPresented: $delete, titleVisibility: .visible) { Button("Delete goal", role: .destructive) { if store.update({ $0.goals.removeAll { $0.id == existing?.id } }) { dismiss() } } }
    }
    private func save() -> Bool {
        guard let target = Money.parse(target), let saved = Money.parse(saved), let account else { store.error = "Enter valid amounts and choose a funding account."; return false }
        guard existing == nil || store.data.currency(existing!.accountID) == store.data.currency(account) else { store.error = "Choose a funding account in the original currency."; return false }
        let goal = Goal(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), symbol: symbol, target: target, saved: saved, accountID: account, deadline: deadline, highPriority: priority)
        return store.update { data in if let i = data.goals.firstIndex(where: { $0.id == goal.id }) { data.goals[i] = goal } else { data.goals.append(goal) } }
    }
}
struct AccountEditor: View {
    @EnvironmentObject var store: HarborStore
    var existing: Account?
    @State private var name = ""
    @State private var balance = ""
    @State private var currency = "CAD"
    var body: some View {
        EditorForm(title: existing == nil ? "New Account" : "Edit Account", save: save) {
            TextField("Account name", text: $name)
            // Existing account units are immutable: changing a label must never masquerade as conversion.
            Picker("Account currency", selection: $currency) { ForEach(Currency.supported, id: \.self) { Text($0).tag($0) } }.disabled(existing != nil)
            TextField("Opening balance (\(currency))", text: $balance).keyboardType(.numbersAndPunctuation)
            Text("Current balance = opening balance + all recorded income − all recorded expenses. Use a negative opening balance for a liability.").font(.caption)
        }.onAppear { if let a = existing { name = a.name; balance = Money.input(a.openingBalance); currency = a.currency } else { currency = store.data.reportingCurrency } }
    }
    private func save() -> Bool {
        guard let cents = Money.parse(balance, allowNegative: true) else { store.error = "Enter a valid opening balance."; return false }
        let account = Account(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), openingBalance: cents, currencyCode: currency, savingsSourceAccountID: existing?.savingsSourceAccountID, savingsReference: existing?.savingsReference)
        return store.update { data in if let i = data.accounts.firstIndex(where: { $0.id == account.id }) { data.accounts[i] = account } else { data.accounts.append(account) } }
    }
}
struct BillEditor: View {
    @EnvironmentObject var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    var existing: Bill?
    @State private var name = ""
    @State private var amount = ""
    @State private var due = Date()
    @State private var account: UUID?
    @State private var category: UUID?
    @State private var delete = false
    @State private var frequency = BillFrequency.monthly
    @State private var autoTrack = false
    var body: some View {
        EditorForm(title: existing == nil ? "New Bill" : "Edit Bill", save: save) {
            // Saving this focused prompt confirms the frequency and due date instead of inventing a cadence.
            if existing?.needsScheduleReview == true { Text(existing?.detectionReviewReason ?? "This subscription was detected automatically. Check its billing frequency and next due date; the monthly schedule is an estimate.").font(.caption).foregroundStyle(.secondary) }
            TextField("Bill name", text: $name)
            TextField("Amount (\(account.map { store.data.currency($0) } ?? store.data.reportingCurrency))", text: $amount).keyboardType(.decimalPad)
            DatePicker("Next due", selection: $due, displayedComponents: .date)
            // Manual bills can opt into the same conservative matcher as confirmed suggestions.
            Picker("Repeats", selection: $frequency) { ForEach(BillFrequency.allCases, id: \.self) { Text($0.label).tag($0) } }
            Toggle("Match payments from imports", isOn: $autoTrack)
            Picker("Account", selection: $account) { Text("Choose account").tag(nil as UUID?); ForEach(store.data.accounts) { Text("\($0.name) · \($0.currency)").tag(Optional($0.id)) } }
            Picker("Category", selection: $category) { Text("Choose category").tag(nil as UUID?); ForEach(store.data.categories.filter { $0.currency == (account.map { store.data.currency($0) } ?? store.data.reportingCurrency) }) { Text($0.name).tag(Optional($0.id)) } }
            Text("Marking paid records an expense and advances the reminder. Import matching uses the bill name, account, expected date, and amount. No automatic payment is made.").font(.caption)
            if existing != nil { Button("Delete bill", role: .destructive) { delete = true } }
        }.onAppear { if let b = existing { name = b.name; amount = Money.input(b.amount); due = b.due; account = b.accountID; category = b.categoryID; frequency = b.frequency; autoTrack = b.matchingMerchant != nil } else { account = store.data.accounts.first?.id; category = store.data.categories.first?.id } }
            .confirmationDialog("Delete this bill reminder?", isPresented: $delete, titleVisibility: .visible) { Button("Delete", role: .destructive) { if let existing, store.update({ RecurringBills.dismiss(existing, in: &$0) }) { dismiss() } } }
    }
    private func save() -> Bool {
        guard let cents = Money.parse(amount), let account, let category else { store.error = "Enter a valid amount, account, and category."; return false }
        guard existing == nil || store.data.currency(existing!.accountID) == store.data.currency(account) else { store.error = "Choose a bill account in the original currency."; return false }
        let bill = Bill(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), amount: cents, due: due, accountID: account, categoryID: category,
                        // Renaming a reminder must not lose the original statement matcher.
                        recurrence: frequency, matchingMerchant: autoTrack ? (existing?.matchingMerchant ?? RecurringBills.merchantKey(name)) : nil,
                        minimumAmount: existing?.amount == cents ? existing?.minimumAmount : cents,
                        maximumAmount: existing?.amount == cents ? existing?.maximumAmount : cents,
                        // Preserve the payment receipt when editing the reminder's details.
                        anchorDay: Calendar.current.component(.day, from: due), lastPaidAt: existing?.lastPaidAt)
        return store.update { data in
            // Disabling matching also prevents rediscovery under an old merchant name after a rename.
            if !autoTrack, let existing {
                let id = RecurringBills.identity(existing.accountID, existing.matchingMerchant ?? existing.name)
                data.ignoredRecurringMerchants = Array(Set((data.ignoredRecurringMerchants ?? []) + [id])).sorted()
            }
            if let i = data.bills.firstIndex(where: { $0.id == bill.id }) { data.bills[i] = bill } else { data.bills.append(bill) }
        }
    }
}
