import SwiftUI
import UniformTypeIdentifiers

// Parsing never mutates HarborStore. Only the confirmed selection reaches its encrypted update path.
struct ImportScreen: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var batch: ImportBatch?
    @State private var filename = ""
    @State private var accountID: UUID?
    @State private var accountName = "Imported chequing"
    @State private var opening = "0"
    @State private var currency = "CAD"
    @State private var currencyConfirmed = false
    @State private var autoSavings = true
    @State private var savingsAccountID: UUID?
    // Importing preserves existing records unless the user explicitly chooses replacement.
    @State private var removeDemo = false
    @State private var selected = Set<UUID>()
    @State private var reconciliation: [UUID: UUID] = [:]
    @State private var duplicates = Set<UUID>()
    // Evidence spans every account before the user picks a destination.
    @State private var accountMatches: [TransactionImport.AccountMatch] = []
    @State private var allowMatchingNewAccount = false
    @State private var editing: ImportRow?
    @State private var parsing: Task<Void, Never>?
    @State private var busy = false
    @State private var message: String?
    @State private var confirming = false
    private var chosenRows: [ImportRow] {
        (batch?.rows.filter { selected.contains($0.id) } ?? []).map { row in
            var next = row; next.reconcileTransactionID = reconciliation[row.id]; return next
        }
    }
    var body: some View {
        List {
            Section {
                Button { choosing = true } label: { Label(batch == nil ? "Choose CSV or PDF" : "Choose another file", systemImage: "doc.badge.plus") }.disabled(busy)
                Text("Imports are processed on this device. CSV dates must be YYYY-MM-DD, with Debit/Credit, Money In/Money Out (with an optional currency-code suffix), or signed Amount columns. PDFs support the validated monthly statement layout and tables with Date, Description, Category, Method, Money In, Money Out, and Balance. Other layouts may need a CSV export; Other layouts can use on-device document recognition on iOS 26 or later; ambiguous rows still require review.").font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView("Reading and categorising statement…") }
                if let message { Text(message).foregroundStyle(.red).accessibilityIdentifier("import.message") }
            }
            if let batch {
                Section("Statement preview") {
                    Text(filename).font(.headline)
                    LabeledContent("Transactions", value: "\(batch.rows.count)").accessibilityIdentifier("import.count")
                    LabeledContent("Deposits", value: store.format(batch.income, currency: currency))
                    LabeledContent("Withdrawals", value: store.format(batch.expenses, currency: currency))
                    if let balance = batch.closingBalance { LabeledContent("Statement closing balance", value: store.format(balance, currency: currency)) }
                    // A symbol alone is insufficient evidence for dollar-denominated statements.
                    Picker("Statement currency", selection: $currency) { ForEach(Currency.supported, id: \.self) { Text($0).tag($0) } }.disabled(batch.currencyCode != nil).accessibilityIdentifier("import.currency")
                    if let detected = batch.currencyCode { Text("Detected from statement: \(detected)").font(.caption) }
                    else { Toggle("Confirm this statement uses \(currency)", isOn: $currencyConfirmed); Text("No unambiguous currency code was found. Check the statement before saving.").font(.caption).foregroundStyle(.orange) }
                    if let accountID, store.data.currency(accountID) != currency { Text("This account uses \(store.data.currency(accountID)). Choose an account in \(currency), or create a new one.").foregroundStyle(.red) }
                    if batch.hasPossibleTransfers { Text("Explicit transfers to savings can be linked below. Other transfers remain for review; Harbor does not infer destinations from an e-transfer alone.").font(.caption).foregroundStyle(.orange).accessibilityIdentifier("import.transferWarning") }
                    if batch.usedDocumentRecognition { Text("Document recognition was used. Check the detected columns, dates, and amounts before saving.").font(.caption).foregroundStyle(.secondary) }
                    if batch.usedOCR { Text("Scanned PDF: text was recognized on-device. Check descriptions and categories carefully before importing.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Destination") {
                    if store.data.isDemo {
                        Toggle("Replace current demo-mode records", isOn: $removeDemo).accessibilityIdentifier("import.removeDemo")
                        Text(removeDemo ? "Confirmation will remove ALL current accounts, transactions, goals, and bills, including records you added in demo mode. Budget categories remain." : "Existing sample records will remain alongside this import.").font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Account", selection: $accountID) {
                        Text("Create new account").tag(nil as UUID?)
                        if !removeDemo { ForEach(store.data.accounts.filter { $0.currency == currency }) { Text($0.name).tag(Optional($0.id)) } }
                    }.accessibilityIdentifier("import.account")
                    if !removeDemo && !accountMatches.isEmpty {
                        Text("This statement overlaps transactions already saved in: " + accountMatches.map { "\($0.account.name) (\($0.count) matches)" }.joined(separator: ", ")).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("import.accountWarning")
                        if accountID == nil {
                            Text("Creating another account would count its opening balance and transactions separately in your net worth. Choose the existing account above to skip duplicate transactions.").font(.caption)
                            Toggle("Create a separate account despite matching transactions", isOn: $allowMatchingNewAccount).accessibilityIdentifier("import.allowMatchingAccount")
                        }
                    }
                    if accountID == nil {
                        TextField("Account name", text: $accountName)
                        TextField("Opening balance (\(currency))", text: $opening).keyboardType(.numbersAndPunctuation)
                        Text(batch.openingBalance == nil ? "Enter the balance immediately before the first selected transaction." : "Opening balance was inferred from the full statement. Adjust it if you deselect transactions.").font(.caption).foregroundStyle(.secondary)
                    } else { Text("Existing opening balances will not change. Use the account this statement belongs to so duplicate checks work across CSV and PDF.").font(.caption).foregroundStyle(.secondary) }
                }
                if chosenRows.contains(where: \.isSavingsTransfer) {
                    Section("Savings transfers") {
                        // Account creation and both linked entries are committed atomically with the import.
                        Toggle("Track transfers in savings", isOn: $autoSavings).accessibilityIdentifier("import.autoSavings")
                        LabeledContent("Amount moved to savings", value: store.format(chosenRows.filter(\.isSavingsTransfer).reduce(0) { $0 + $1.amount }, currency: currency)).accessibilityIdentifier("import.savingsTotal")
                        if autoSavings {
                            Picker("Savings destination", selection: $savingsAccountID) {
                                Text("Create or reuse linked Savings account").tag(nil as UUID?)
                                ForEach(store.data.accounts.filter { $0.currency == currency && $0.id != accountID && !removeDemo }) { Text($0.name).tag(Optional($0.id)) }
                            }
                            Text("Harbor will credit savings and link the withdrawal. These movements do not count as spending or income. A new account starts at zero and tracks these transfers only; its full bank balance may be different.").font(.caption)
                        }
                    }
                }
                Section("Automatic categories") {
                    Text(AppleCategoryModel.status).font(.caption).foregroundStyle(.secondary)
                    // Explain the same exception-only review policy enforced by the shared save path.
                    Text("Statement labels and reviewed merchant history take priority. Apple’s on-device model suggests from existing and standard categories when available. Uncertain rows retain their source label. Tap any row to override. Clear categories no longer need review; uncertain transactions and transfers stay flagged.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Recurring bills") {
                    // Analysis uses the committed selection, so unchecked rows never become bill evidence.
                    Text("After saving, Harbor tracks clear recurring bills automatically. Explicit services such as iCloud use Subscription. Only uncertain bills or billing schedules prompt for review in Settings → Recurring Bills. Matching never creates another expense.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Apple Pay reconciliation") {
                    Text("A checkmark confirms an existing tap instead of adding spending. Use the link button to choose a capture within three days, including changed final amounts. Review uncertain matches; separate purchases stay separate.").font(.caption)
                    LabeledContent("Confirm existing purchases", value: "\(chosenRows.filter { $0.reconcileTransactionID != nil }.count)")
                }
                Section("Review selection") {
                    LabeledContent("Selected", value: "\(selected.count) of \(batch.rows.count)").accessibilityIdentifier("import.selected")
                    LabeledContent("Selected deposits", value: store.format(chosenRows.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }, currency: currency))
                    LabeledContent("Selected withdrawals", value: store.format(chosenRows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }, currency: currency))
                    if !duplicates.isEmpty { Text("\(duplicates.count) possible duplicates matched by account, date, description, amount, and direction. They are unchecked unless selected to confirm an existing Apple Pay purchase; explicitly include legitimate separate purchases you want to keep.").font(.caption).foregroundStyle(.secondary) }
                    Button("Recheck duplicates") { resetSelection() }
                    Button("Deselect all") { selected.removeAll() }
                    Text("Tap a transaction to correct its fields. Equivalent labels reuse a category (for example, Gas & Fuel uses Transport). Your renamed categories and manual corrections are retained; new categories start without a budget. Clear transactions are saved without review flags. Uncertain categories and transfers remain flagged.").font(.caption).foregroundStyle(.secondary)
                    // Duplicate-only runs can save a receipt while adding no financial entries.
                    Button(selected.isEmpty ? "Record skipped import" : "Import \(selected.count) transactions") { confirming = true }.disabled((selected.isEmpty && (duplicates.isEmpty || accountID == nil || removeDemo)) || busy || !currencyConfirmed || (accountID != nil && store.data.currency(accountID!) != currency) || (accountID == nil && !removeDemo && !accountMatches.isEmpty && !allowMatchingNewAccount)).accessibilityIdentifier("import.commit")
                }
                Section("Transactions") {
                    ForEach(batch.rows) { row in
                        HStack {
                            Toggle("Include \(row.merchant)", isOn: Binding(get: { selected.contains(row.id) }, set: { if $0 { selected.insert(row.id) } else { selected.remove(row.id) } })).labelsHidden()
                            Button { editing = row } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(row.merchant).foregroundStyle(.primary); Spacer(); Text(store.format(row.signedAmount, currency: currency)).foregroundStyle(row.kind == .income ? HarborStyle.teal : HarborStyle.navy) }
                                    Text("\(row.date.formatted(date: .abbreviated, time: .omitted)) · \(row.category)").font(.caption).foregroundStyle(.secondary)
                                    if let reason = row.categoryReason { Text(reason).font(.caption2).foregroundStyle(.secondary) }
                                    if row.isSavingsTransfer { Text("Transfer to savings").font(.caption).foregroundStyle(.secondary) }
                                    if reconciliation[row.id] != nil { Text("Confirm existing Apple Pay purchase").font(.caption).foregroundStyle(HarborStyle.teal) }
                                    else if duplicates.contains(row.id) { Text("Possible duplicate").font(.caption).foregroundStyle(.orange) }
                                }
                            }.buttonStyle(.plain)
                            if row.kind == .expense, accountID != nil {
                                Menu {
                                    Button("Import as separate purchase") { reconciliation[row.id] = nil; selected.insert(row.id) }
                                    ForEach(TransactionImport.captureCandidates(row, in: store.data, account: accountID)) { capture in
                                        Button("Confirm \(capture.merchant) · \(store.format(capture.amount, currency: currency)) · \(capture.date.formatted(date: .abbreviated, time: .omitted))") {
                                            reconciliation[row.id] = capture.id; selected.insert(row.id)
                                        }
                                    }
                                } label: {
                                    Image(systemName: reconciliation[row.id] == nil ? "link" : "checkmark.seal.fill")
                                }.accessibilityLabel(reconciliation[row.id] == nil ? "Match Apple Pay purchase" : "Apple Pay confirmation selected")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Import transactions")
        .onChange(of: currency) { _, _ in if batch?.currencyCode == nil { currencyConfirmed = false }; savingsAccountID = nil; resetSelection() }
        .onChange(of: accountID) { _, _ in allowMatchingNewAccount = false; resetSelection() }
        .onChange(of: removeDemo) { _, value in allowMatchingNewAccount = false; if value { accountID = nil; savingsAccountID = nil }; resetSelection() }
        .onDisappear { parsing?.cancel() }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .pdf]) { result in
            do { read(try result.get()) } catch { message = error.localizedDescription }
        }
        .sheet(item: $editing) { row in
            ImportRowEditor(row: row, currency: currency) { updated in
                if let index = self.batch?.rows.firstIndex(where: { $0.id == updated.id }) { self.batch?.rows[index] = updated }
                // User edits can change duplicate identity; keep the other choices intact.
                if let rows = self.batch?.rows {
                    duplicates = TransactionImport.duplicates(rows, in: store.data, account: accountID)
                    accountMatches = TransactionImport.matchingAccounts(rows, in: store.data)
                    allowMatchingNewAccount = false
                    // Editing a matched row must never silently turn confirmation into duplicate spending.
                    if reconciliation.removeValue(forKey: updated.id) != nil {
                        selected.remove(updated.id)
                        message = "Edited Apple Pay match cleared. Match this row again or explicitly include it as a separate purchase."
                    }
                }
            }
        }
        .confirmationDialog(selected.isEmpty ? "Record this import in history without adding transactions?" : "Save \(selected.count) transactions\(removeDemo ? " and remove all current records" : "")?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Save import", role: removeDemo ? .destructive : nil) { commit() }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Import complete", isPresented: Binding(get: { completedCount != nil }, set: { if !$0 { completedCount = nil; dismiss() } })) {
            Button("Done") { completedCount = nil; dismiss() }
        } message: { Text(completedCount == 0 ? "Import receipt saved. No transactions were added. See Settings → Import history for details." : "\(completedCount ?? 0) rows saved securely. Matched Apple Pay purchases were updated rather than added again. See Settings → Import history for added, matched, and skipped counts.") }
    }
    @State private var completedCount: Int?
    private func resetSelection() {
        guard let batch else { return }
        duplicates = TransactionImport.duplicates(batch.rows, in: store.data, account: accountID)
        reconciliation = [:]
        // Only a one-to-one exact match is selected automatically, including across identical statement rows.
        let proposals = batch.rows.compactMap { row -> (UUID, UUID)? in
            guard let target = TransactionImport.exactCapture(row, in: store.data, account: accountID) else { return nil }
            return (row.id, target)
        }
        for (row, target) in proposals where proposals.filter({ $0.1 == target }).count == 1 {
            reconciliation[row] = target
        }
        selected = Set(batch.rows.map(\.id)).subtracting(duplicates).union(reconciliation.keys)
    }
    private func read(_ url: URL) {
        parsing?.cancel(); busy = true; message = nil; batch = nil; selected = []; accountMatches = []; allowMatchingNewAccount = false; filename = url.lastPathComponent
        let worker = Task.detached(priority: .userInitiated) { () async throws -> ImportBatch in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= TransactionImport.maximumBytes else { throw FinanceError(message: "Choose a file no larger than 25 MB.") }
            try Task.checkCancellation()
            // Bound reads even when a document provider cannot report its file size.
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var bytes = Data()
            while true {
                try Task.checkCancellation()
                let chunk = try handle.read(upToCount: min(1_048_576, TransactionImport.maximumBytes - bytes.count + 1)) ?? Data()
                if chunk.isEmpty { break }
                guard bytes.count + chunk.count <= TransactionImport.maximumBytes else { throw FinanceError(message: "Choose a file no larger than 25 MB.") }
                bytes.append(chunk)
            }
            switch url.pathExtension.lowercased() {
            case "csv": return try TransactionImport.csv(bytes)
            case "pdf": return try await StatementPDFImport.parseWithDocumentRecognition(bytes)
            default: throw FinanceError(message: "Choose a CSV or PDF statement.")
            }
        }
        parsing = Task {
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                // Enrich only category fields; financial reconciliation has already succeeded.
                var enriched = result
                let destination = TransactionImport.suggestedAccount(result.rows, in: store.data) ?? accountID
                enriched.rows = try await Categorization.prepare(result.rows, in: store.data, accountID: destination, currency: result.currencyCode ?? destination.map { store.data.currency($0) } ?? store.data.reportingCurrency)
                try Task.checkCancellation()
                batch = enriched
                currency = result.currencyCode ?? accountID.map { store.data.currency($0) } ?? store.data.reportingCurrency
                currencyConfirmed = result.currencyCode != nil
                savingsAccountID = nil
                opening = Money.input(result.openingBalance ?? 0)
                accountMatches = TransactionImport.matchingAccounts(result.rows, in: store.data)
                // Reimporting an exact statement uses its existing account; tied accounts require a choice.
                if !removeDemo, let existing = TransactionImport.suggestedAccount(result.rows, in: store.data) { accountID = existing }
                resetSelection()
                busy = false
            } catch is CancellationError { busy = false }
            catch {
                // Keep detailed parser errors in-app; optional system alerts contain no statement details.
                message = error.localizedDescription; busy = false
                ReminderNotifications.shared.reportFailure()
            }
        }
    }
    private func commit() {
        guard let batch else { message = "Choose a statement first."; return }
        guard let cents = accountID == nil ? Money.parse(opening, allowNegative: true) : 0 else { message = "Enter a valid opening balance with at most two decimal places."; return }
        let rows = chosenRows
        let account = accountID == nil ? Account(name: accountName.trimmingCharacters(in: .whitespacesAndNewlines), openingBalance: cents, currencyCode: currency) : nil
        // The receipt and selected rows share one atomic encrypted save, including duplicate-only imports.
        if store.update({ try TransactionImport.applyWithHistory(rows, batch: batch, filename: filename, to: &$0, accountID: accountID, newAccount: account, removeDemo: removeDemo, allowMatchingNewAccount: allowMatchingNewAccount, currencyCode: currency, autoSavings: autoSavings, savingsAccountID: savingsAccountID) }) {
            completedCount = rows.count
        } else { message = store.error; store.error = nil }
    }
}

// Corrections apply to the preview only; cancellation leaves the saved ledger untouched.
private struct ImportRowEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var row: ImportRow
    var currency: String
    var save: (ImportRow) -> Void
    @State private var amount = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Description", text: $row.merchant)
                DatePicker("Date", selection: $row.date, displayedComponents: .date)
                Picker("Direction", selection: $row.kind) { Text("Expense").tag(TransactionKind.expense); Text("Income").tag(TransactionKind.income) }
                TextField("Amount (\(currency))", text: $amount).keyboardType(.decimalPad)
                if row.kind == .expense { Toggle("Transfer to savings", isOn: Binding(get: { row.isSavingsTransfer }, set: { row.savingsTransfer = $0 })) }
                TextField("Category", text: $row.category)
                    .onChange(of: row.category) { _, _ in row.manualCategory = true; row.suggestedCategoryID = nil; row.categoryReason = "Your manual category" }
                if let reason = row.categoryReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                if let source = row.sourceCategory { Text("Statement label: " + source).font(.caption).foregroundStyle(.secondary) }
                TextField("Note", text: $row.note, axis: .vertical)
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Review transaction")
                .onAppear { amount = Money.input(row.amount) }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard let cents = Money.parse(amount), cents > 0, !row.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  !row.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter a description, category, and positive amount."; return }
                            row.amount = cents; row.merchant = row.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
                            row.category = row.category.trimmingCharacters(in: .whitespacesAndNewlines)
                            save(row); dismiss()
                        }
                    }
                }
        }
    }
}
