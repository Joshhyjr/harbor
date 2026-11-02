import SwiftUI
import UniformTypeIdentifiers

// Settings is a compact directory; the existing ledger tools live in focused destinations.
struct SettingsScreen: View {
    @EnvironmentObject private var lock: HarborLock
    @EnvironmentObject private var store: HarborStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(HarborAppearance.preferenceKey) private var appearance = HarborAppearance.system.rawValue

    var body: some View {
        Screen {
            HarborCard(dark: true) {
                // Decorative icons keep their size; accessibility text gets the full card width.
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        privacyIcon
                        privacyMessage
                    }
                } else {
                    HStack(spacing: 16) {
                        privacyIcon
                        privacyMessage
                        Spacer(minLength: 0)
                    }
                }
            }
            HarborCard {
                Text("Preferences").font(.title3.bold())
                // Stack the segmented control below its label so long labels and large text fit.
                VStack(alignment: .leading, spacing: 12) {
                    Label { Text("Appearance") } icon: { IconTile(symbol: "sun.max").dynamicTypeSize(...DynamicTypeSize.xxxLarge) }
                    Picker("Appearance", selection: $appearance) {
                        ForEach(HarborAppearance.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("settings.appearance")
                }
                Divider()
                HStack(spacing: 12) {
                    IconTile(symbol: "globe").dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    Text("Default currency")
                    Spacer(minLength: 0)
                    // A Picker outside Form needs an explicit visible row title.
                    ReportingCurrencyPicker(title: "Default currency").labelsHidden()
                }
                Text("System follows your device’s appearance. Currency applies to reports and new accounts.")
                    .font(.caption).foregroundStyle(.secondary)
                LearnMoreLink(title: "Reporting currencies", paragraphs: ["Accounts retain their original currency. Reports show one currency at a time; no exchange rates or conversions are applied."]).foregroundStyle(HarborStyle.blue)
            }
            HarborCard {
                Text("Manage").font(.title3.bold())
                detailLink("Accounts", symbol: "creditcard", destination: .accounts)
                Divider()
                detailLink("Categories", symbol: "tag", destination: .categories)
                Divider()
                NavigationLink { BillsScreen().navigationBarTitleDisplayMode(.inline) } label: {
                    SettingsNavigationLabel(title: "Recurring Bills", symbol: "calendar")
                }
            }
            HarborCard {
                Text("Security & data").font(.title3.bold())
                // Both directions still use HarborLock's fresh system authentication.
                Toggle(isOn: Binding(get: { lock.enabled }, set: { value in Task { await lock.setEnabled(value) } })) {
                    HStack(spacing: 12) { IconTile(symbol: "faceid").dynamicTypeSize(...DynamicTypeSize.xxxLarge); Text("Face ID & passcode") }
                }.disabled(lock.authenticating).accessibilityIdentifier("settings.appLock")
                if let message = lock.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                LearnMoreLink(title: "App security", paragraphs: ["Records stay encrypted on this device. App lock adds Face ID, Touch ID, or your device passcode and requires authentication at launch and after Harbor enters the background."]).foregroundStyle(HarborStyle.blue)
                Divider()
                NavigationLink { ApplePayShortcutsScreen().navigationBarTitleDisplayMode(.inline) } label: {
                    SettingsNavigationLabel(title: "Apple Pay Shortcuts", symbol: "bolt")
                }.disabled(store.recoveryNeeded)
                Divider()
                detailLink("Imports & reconciliation", symbol: "doc.badge.plus", destination: .imports)
                Divider()
                NavigationLink { BackupScreen().navigationBarTitleDisplayMode(.inline) } label: {
                    SettingsNavigationLabel(title: "Backups and recovery", symbol: "lock.doc")
                }
            }
            HarborCard {
                NavigationLink { SettingsDetailScreen(destination: .reset) } label: {
                    SettingsNavigationLabel(title: "Reset Harbor", symbol: "trash", destructive: true)
                }.accessibilityIdentifier("settings.reset")
            }
        }
        .foregroundStyle(HarborStyle.navy)
        .navigationBarTitleDisplayMode(.large)
    }

    private var privacyIcon: some View {
        Image(systemName: "lock.shield.fill").font(.system(size: 28))
            .foregroundStyle(HarborStyle.heroAccent).accessibilityHidden(true)
    }

    private var privacyMessage: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Private by design").font(.headline)
            Text("Your finances stay on this device.").font(.subheadline).foregroundStyle(.white.opacity(0.85))
        }
    }

    private func detailLink(_ title: String, symbol: String, destination: SettingsDestination) -> some View {
        NavigationLink { SettingsDetailScreen(destination: destination) } label: {
            SettingsNavigationLabel(title: title, symbol: symbol)
        }.accessibilityIdentifier(destination.identifier)
    }
}

// Keep row styling local to Settings rather than changing every Harbor card or navigation link.
private struct SettingsNavigationLabel: View {
    let title: String
    let symbol: String
    var destructive = false
    var body: some View {
        HStack(spacing: 12) {
            if destructive {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.red)
                    .frame(width: 44, height: 44).background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
            } else { IconTile(symbol: symbol).dynamicTypeSize(...DynamicTypeSize.xxxLarge) }
            Text(title).foregroundStyle(destructive ? Color.red : HarborStyle.navy)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
        }.frame(minHeight: 44).contentShape(Rectangle())
    }
}

private enum SettingsDestination: String {
    case accounts = "Accounts", categories = "Categories", imports = "Imports & reconciliation", reset = "Reset Harbor"
    var identifier: String {
        switch self {
        case .accounts: "settings.accounts"
        case .categories: "settings.categories"
        case .imports: "settings.imports"
        case .reset: "settings.reset"
        }
    }
}

// Detail routes retain the existing save, recovery, and destructive-action safeguards.
private struct SettingsDetailScreen: View {
    let destination: SettingsDestination
    @EnvironmentObject var store: HarborStore
    @State private var clearAll = false
    @State private var addingAccount = false
    @State private var editingAccount: Account?
    @State private var clear = false
    @State private var simplify = false
    @State private var simplificationConfirmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var status = ""
    var body: some View {
        List {
            if destination == .categories {
                // Cleanup is reviewable and preserves the aggregate category budget.
                Section("Categories") {
                    NavigationLink("Manage categories") { CategoryManagementScreen() }
                    Text(AppleCategoryModel.status).font(.caption).foregroundStyle(.secondary)
                    // Completed cleanup is a stable state, not a button that rewrites the same ledger.
                    if store.categorySimplificationNeeded {
                        Button("Simplify combined categories") { simplify = true }
                            .disabled(store.recoveryNeeded).accessibilityIdentifier("settings.simplify")
                        Text("Combine matching categories and keep your total budget.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label(simplificationConfirmed ? "Categories simplified" : "Categories up to date", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(HarborStyle.teal).accessibilityIdentifier("settings.simplified")
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                        if simplificationConfirmed {
                            Text("Total budget preserved.").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("settings.simplifyResult")
                        }
                    }
                    LearnMoreLink(title: "Category simplification", paragraphs: ["Use Rent, Utilities, Dining, Health, and Entertainment instead of combined labels. Matching categories merge and their budgets add together. Cleanup is available only when it would change your categories; it can be offered again if combined categories are added later."])
                }.animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8), value: store.categorySimplificationNeeded)
            }
            if destination == .accounts {
                Section("Accounts") {
                    ForEach(store.data.accounts) { account in Button { editingAccount = account } label: { HStack { Text(account.name); Spacer(); Text(store.format(store.data.balance(account.id), currency: account.currency)).monospacedDigit() }.foregroundStyle(HarborStyle.navy) } }
                    if store.data.accounts.contains(where: { $0.savingsSourceAccountID != nil }) {
                        Text("Imported savings transfers may not reflect the full account balance.").font(.caption).foregroundStyle(.secondary)
                        LearnMoreLink(title: "Savings balances", paragraphs: ["Automatically created savings accounts track only the imported transfers. Set an opening balance or import the savings statement to reconcile a full bank balance."])
                    }
                    if !store.data.savingsCandidates.isEmpty { NavigationLink { SavingsReviewScreen() } label: { Label("Attach existing savings transfers", systemImage: "arrow.left.arrow.right") } }
                    Button { addingAccount = true } label: { Label("Add account", systemImage: "plus.circle") }
                }
            }
            if destination == .imports {
                Section("Your Data") {
                    // Transaction imports append a reviewed selection; JSON restore replaces the whole ledger.
                    NavigationLink { ImportScreen() } label: { Label("Import CSV or PDF", systemImage: "doc.badge.plus") }.disabled(store.recoveryNeeded)
                    // Saved receipts and balance checks use the same encrypted on-device ledger.
                    NavigationLink { ImportHistoryScreen() } label: { Label("Import history", systemImage: "clock.arrow.circlepath") }
                    NavigationLink { MonthlyReconciliationScreen() } label: { Label("Monthly reconciliation", systemImage: "checkmark.seal") }.disabled(store.recoveryNeeded)
                    Text("Export a backup before changing devices or removing Harbor.").font(.caption).foregroundStyle(.secondary)
                    LearnMoreLink(title: "Backups and local storage", paragraphs: ["Records use AES-256-GCM encryption, a device-only Keychain key, and iOS file protection. Use an encrypted portable backup and store its recovery key separately. Export before changing devices or removing the app; the encrypted ledger is excluded from device backups. No bank sync is configured."])
                }
            }
            if destination == .reset {
                // Keep complete deletion separate from the demo-only shortcut and explain exactly what survives.
                Section("Reset Harbor") {
                    if store.data.isDemo { Button("Start fresh with my own data", role: .destructive) { clear = true } }
                    Button("Clear all data", role: .destructive) { clearAll = true }
                        .disabled(store.recoveryNeeded).accessibilityIdentifier("settings.clearAll")
                    Text("Permanently delete Harbor’s local records. Export a backup first.").font(.caption).foregroundStyle(.secondary)
                    LearnMoreLink(title: "Reset Harbor", paragraphs: ["Delete all accounts, transactions, budget categories and limits, goals, bills, and profile details from Harbor on this device. Export a backup first to keep a copy. Pending Apple Pay captures are deleted and capture is disabled. Appearance and app lock are retained; exported files are not deleted."])
                }
            }
            if !status.isEmpty { Section { Text(status).foregroundStyle(HarborStyle.teal).accessibilityIdentifier("settings.status") } }
        }
        .navigationTitle(destination.rawValue).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingAccount) { AccountEditor() }.sheet(item: $editingAccount) { AccountEditor(existing: $0) }
        .confirmationDialog("Simplify categories? Combined housing becomes Utilities; entries named Rent move to Rent. Rent starts at zero unless it already has a budget. Other existing limits are retained or added when categories merge. You can adjust each budget afterward.", isPresented: $simplify, titleVisibility: .visible) {
            Button("Simplify categories") {
                // Recheck at confirmation time; stale dialogs cannot trigger a duplicate save.
                guard store.categorySimplificationNeeded else { return }
                if store.update({ try $0.simplifyCategories() }) { simplificationConfirmed = true }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Clear all Harbor data?", isPresented: $clearAll) {
            Button("Clear all data", role: .destructive) {
                if store.clearAllData() {
                    status = "All data cleared. Add an account to begin."
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes all accounts, transactions, budgets, goals, bills, profile details, and pending Shortcut captures. Capture is disabled. Restore requires an exported backup. Appearance, app lock, and exported files are kept.")
        }
        .confirmationDialog("Remove demo accounts, transactions, bills, and goals? Budget categories will be kept.", isPresented: $clear, titleVisibility: .visible) {
            Button("Start fresh", role: .destructive) {
                if store.update({ data in
                    data.isDemo = false; data.accounts = []; data.transactions = []; data.goals = []; data.bills = []
                    // Demo replacement also clears receipts/checks belonging to those removed accounts.
                    data.statementImports = nil; data.statementBalanceChecks = nil
                }) { status = "Ready for your data. Add an account to begin." }
            }
        }
    }
}

// Personal details live behind the person icon; saving still acknowledges only persisted changes.
struct ProfileScreen: View {
    @EnvironmentObject var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var nameSaved = false
    @FocusState private var editingName: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section("Your name") {
                    TextField("Your name", text: $name)
                        .textContentType(.givenName).submitLabel(.done).focused($editingName)
                        .onSubmit { saveName() }.accessibilityIdentifier("profile.name")
                    Button("Save name") { saveName() }
                        .disabled(cleanName.isEmpty || cleanName == store.data.name)
                        .accessibilityIdentifier("profile.saveName")
                }
                // Settings stays reachable from every tab through the shared profile button.
                Section {
                    NavigationLink {
                        SettingsScreen().navigationTitle("Settings")
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("profile.done") } }
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }.accessibilityIdentifier("profile.settings")
                }
            }.navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
                // Toolbar controls belong inside the navigation stack, alongside their screen content.
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("profile.done") } }
                .onAppear { name = store.data.name }
                .alert("Name updated", isPresented: $nameSaved) { Button("Done", role: .cancel) { } } message: {
                    Text("Your name is now \(store.data.name).")
                }
        }
    }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func saveName() {
        guard !cleanName.isEmpty, cleanName != store.data.name else { return }
        if store.update({ $0.name = cleanName }) {
            name = store.data.name
            editingName = false
            nameSaved = true
        }
    }
}

struct BillsScreen: View {
    @EnvironmentObject var store: HarborStore
    @State private var creating = false
    @State private var editing: Bill?
    @State private var tracking: RecurringSuggestion?
    private var suggestions: [RecurringSuggestion] { RecurringBills.suggestions(in: store.data) }
    var body: some View {
        Screen {
            // Only incomplete evidence requests confirmation; clear recorded schedules are already tracked.
            Text("Clear recurring bills are tracked automatically. Review only the prompts below.").font(.caption).foregroundStyle(.secondary)
            LearnMoreLink(title: "Automatic recurring bills", paragraphs: ["Explicit services such as Apple iCloud are categorised as Subscription. Apple Intelligence can suggest Subscription for unfamiliar descriptions when available. Harbor checks payment dates and amounts itself: three clear, regularly spaced payments with stable amounts in Rent, Utilities, Insurance, or Subscription can be tracked automatically. A named subscription with too little history appears immediately with an estimated monthly schedule and a prompt to check it. Generic Apple charges do not identify a specific subscription. Manual category corrections, edited bills, and deleted reminders are respected. Everything stays on this device."])
            if store.data.bills.isEmpty && suggestions.isEmpty { EmptyCard(title: "No recurring bills", detail: "Create a bill or import several months of history to find recurring payments.") }
            ForEach(store.data.bills.sorted { $0.due < $1.due }) { bill in
                HarborCard {
                    HStack { IconTile(symbol: "calendar"); VStack(alignment: .leading) { Text(bill.name).font(.headline); Text("Due \(bill.due.formatted(date: .abbreviated, time: .omitted))").font(.caption); Text("\(bill.frequency.label) · \(store.data.accountName(bill.accountID))").font(.caption).foregroundStyle(.secondary) }; Spacer(); MoneyLabel(cents: bill.amount, size: 20, currency: store.data.currency(bill.accountID)) }
                    // Keep the subscription classification visible alongside the detected reminder.
                    Text(store.data.category(bill.categoryID)?.name ?? "Other").font(.caption).accessibilityIdentifier("bill.category." + bill.name)
                    if bill.needsScheduleReview == true {
                        Text(bill.detectionReviewReason ?? "Review needed: billing frequency is not established. Monthly is an estimate; check the frequency and next due date.").font(.caption).foregroundStyle(.orange).accessibilityIdentifier("bill.scheduleReview." + bill.name)
                    } else if bill.matchingMerchant != nil { Text("Auto-tracking imports · \(store.data.transactions.filter { $0.recurringBillID == bill.id }.count) matched payments").font(.caption).foregroundStyle(.secondary) }
                    // Persist first; only a successful ledger update replaces the action with Paid.
                    HStack {
                        Button("Edit") { editing = bill }.buttonStyle(.bordered).accessibilityIdentifier("bill.edit." + bill.name)
                        Spacer()
                        if bill.needsScheduleReview == true {
                            Button("Review schedule") { editing = bill }.buttonStyle(.borderedProminent).accessibilityIdentifier("bill.reviewSchedule." + bill.name)
                        } else if bill.isPaymentComplete() {
                            Label("Paid", systemImage: "checkmark.circle.fill").foregroundStyle(HarborStyle.teal)
                                .accessibilityIdentifier("bill.paid." + bill.name)
                        } else {
                            Button("Mark paid") { store.update { try $0.payBill(bill.id, expectedDue: bill.due) } }
                                .buttonStyle(.borderedProminent).accessibilityIdentifier("bill.markPaid." + bill.name)
                        }
                    }
                    if let paid = bill.lastPaidAt {
                        Text("Last paid \(paid.formatted(date: .abbreviated, time: .omitted)) · Next due \(bill.due.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("bill.paymentDetails." + bill.name)
                    }
                }
            }
            ForEach(suggestions) { suggestion in
                HarborCard {
                    Text("Review recurring bill: \(suggestion.latest.merchant)").font(.headline)
                    Text("\(suggestion.frequency.label) · \(suggestion.payments.count) payments · \(store.data.accountName(suggestion.latest.accountID))").font(.caption)
                    Text(suggestion.minimum == suggestion.maximum ? store.format(suggestion.minimum, currency: store.data.currency(suggestion.latest.accountID)) : "\(store.format(suggestion.minimum, currency: store.data.currency(suggestion.latest.accountID)))–\(store.format(suggestion.maximum, currency: store.data.currency(suggestion.latest.accountID))) · Variable amount").font(.subheadline)
                    Text("Next expected: \(suggestion.due.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                    ForEach(suggestion.payments) { payment in
                        HStack { Text(payment.date.formatted(date: .abbreviated, time: .omitted)); Spacer(); Text(store.format(payment.amount, currency: store.data.currency(payment.accountID))) }.font(.caption)
                    }
                    Button("Track this bill") { tracking = suggestion }.buttonStyle(.borderedProminent).accessibilityIdentifier("bill.track." + suggestion.latest.merchant)
                }
            }
            Button { creating = true } label: { Label("Create recurring bill", systemImage: "plus.circle").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
        }.navigationTitle("Recurring Bills")
            .sheet(isPresented: $creating) { BillEditor() }.sheet(item: $editing) { BillEditor(existing: $0) }
            .confirmationDialog("Track \(tracking?.latest.merchant ?? "this bill")? Confirm these are recurring payments. Future imports with the same description and account, a similar amount, and a date near the next due date will update the reminder without adding another expense.", isPresented: Binding(get: { tracking != nil }, set: { if !$0 { tracking = nil } }), titleVisibility: .visible) {
                Button("Confirm recurring bill") { if let tracking { store.update { try RecurringBills.confirm(tracking, in: &$0) } }; tracking = nil }
                Button("Cancel", role: .cancel) { tracking = nil }
            }

    }
}
struct NotificationsScreen: View {
    @EnvironmentObject var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                // Purchase alerts are explicitly enabled here or from Apple Pay setup.
                PurchaseNotificationSection()
                // A deliberate daily review earns progress; all system reminder categories remain opt-in.
                DailyCheckInCard(location: "notifications")
                ReminderSettingsSection()
                Section("Review Inbox") {
                    let count = store.data.transactions.filter(\.needsReview).count
                    // Unlike the monthly briefing, this inbox intentionally covers the entire ledger.
                    Text(count == 0 ? "All transactions reviewed across all months." : "\(count) transaction\(count == 1 ? " needs" : "s need") review across all months. In Activity, select a month and tap Needs Review.")
                        .accessibilityIdentifier("notifications.reviewCount")
                }
                // Surface only unresolved schedules; automatically established bills need no approval.
                Section("Recurring bill review") {
                    let pending = store.data.bills.filter { $0.needsScheduleReview == true }
                    if pending.isEmpty { Text("No billing schedules need review.") }
                    ForEach(pending) { bill in
                        NavigationLink("Review \(bill.name) billing schedule") { BillEditor(existing: bill) }
                    }
                    let uncertain = RecurringBills.suggestions(in: store.data).count
                    if uncertain > 0 { Text("\(uncertain) possible recurring bills need a check in Settings → Recurring Bills.").font(.caption) }
                }
                Section("Budget Alerts") {
                    // Alerts always evaluate today, independently of the month selected elsewhere.
                    let plan = AutomaticBudgets.calculate(data: store.data, month: Date())
                    let categories = store.data.reportingCategories.map { plan.resolved($0) }.filter { $0.limit > 0 && Double(store.data.total(.expense, in: Date(), category: $0.id)) >= Double($0.limit) * 0.85 }
                    if categories.isEmpty { Text("All budgets are on track.") }
                    ForEach(categories) { category in Label("\(category.name): \(store.format(store.data.total(.expense, in: Date(), category: category.id))) of \(store.format(category.limit))", systemImage: "exclamationmark.circle") }
                }
                Section("Upcoming & Overdue Bills") {
                    let bills = store.data.bills.filter { $0.due <= Calendar.current.date(byAdding: .day, value: 7, to: Date())! }
                    if bills.isEmpty { Text("No bills due in the next seven days.") }
                    ForEach(bills) { bill in VStack(alignment: .leading) { Text(bill.name).font(.headline); Text("\(store.format(bill.amount, currency: store.data.currency(bill.accountID))) · \(bill.due.formatted(date: .abbreviated, time: .omitted))").font(.caption) } }
                }
                Section { Text("Alerts are scheduled locally on this iPhone. Harbor cannot detect missed Wallet triggers or bank-side failures, and reminders do not confirm that a bill has been paid.").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("Notifications").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// Previously imported withdrawals are converted in place only after the user reviews a concrete selection.
struct SavingsReviewScreen: View {
    @EnvironmentObject var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<UUID>()
    @State private var confirming = false
    var body: some View {
        List {
            Section {
                Text("Review transfers into savings. Linked savings balances start at zero.").font(.caption)
                LearnMoreLink(title: "Savings transfer review", paragraphs: ["These withdrawals explicitly say they moved to savings. Harbor will create or reuse a linked Savings account for each source and transfer reference. It will preserve the source balance and stop counting the movement as spending or income. Savings starts at zero and reflects these tracked transfers only."])
            }
            ForEach(store.data.savingsCandidates) { transaction in
                Toggle(isOn: Binding(get: { selected.contains(transaction.id) }, set: { if $0 { selected.insert(transaction.id) } else { selected.remove(transaction.id) } })) {
                    VStack(alignment: .leading) {
                        Text(transaction.merchant)
                        Text("\(store.data.accountName(transaction.accountID)) · \(transaction.date.formatted(date: .abbreviated, time: .omitted)) · \(store.format(transaction.amount, currency: store.data.currency(transaction.accountID)))").font(.caption)
                    }
                }
            }
            Button("Attach \(selected.count) savings transfers") { confirming = true }.disabled(selected.isEmpty)
        }.navigationTitle("Review savings")
            .onAppear { selected = Set(store.data.savingsCandidates.map(\.id)) }
            .confirmationDialog("Attach these withdrawals to linked Savings accounts? Existing source balances stay unchanged. Savings balances will represent the selected movements, not assumed full bank balances.", isPresented: $confirming, titleVisibility: .visible) {
                Button("Attach savings transfers") { if store.update({ try $0.trackExistingSavingsTransfers(selected) }) { dismiss() } }
            }
    }
}

// Existing ledgers are organized only after the user reviews a concrete candidate snapshot.
private struct CategoryPlan: Identifiable {
    let id = UUID()
    let original: FinanceData
    var next: FinanceData
    let detail: String
}
struct CategoryManagementScreen: View {
    @EnvironmentObject private var store: HarborStore
    @State private var editing: Category?
    @State private var creating = false
    @State private var plan: CategoryPlan?
    @State private var work: Task<Void, Never>?
    @State private var busy = false
    @State private var workID = UUID()
    @State private var merging: Category?
    @State private var showSaved = false
    var body: some View {
        // Count once per refresh, across currencies and including saved on-device model assignments.
        let counts = store.data.categoryTransactionCounts(in: store.month)
        let displayedCategories = store.data.categories.filter { showSaved || counts[$0.id] != nil }.map(store.budgetCategory)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return List {
            Section {
                MonthPicker()
                Toggle("Show all saved categories", isOn: $showSaved).accessibilityIdentifier("categories.showSaved")
                Text("Categories used by this month’s transactions, including saved Apple Intelligence suggestions. All account currencies are included.").font(.caption)
                LearnMoreLink(title: "Managing categories", paragraphs: ["Rename categories to suit you. Imports reuse the same category after a rename. Merge duplicates below; existing budget limits are added together. Unused categories with a budget are kept."])
                Text(AppleCategoryModel.status).font(.caption).foregroundStyle(.secondary)
                Button("Review category cleanup") { prepareCleanup() }.disabled(busy || store.recoveryNeeded)
                Button("Auto-categorise unreviewed transactions") { prepareSuggestions() }.disabled(busy || store.recoveryNeeded)
                if busy { ProgressView("Checking categories on this device…") }
            }
            Section(showSaved ? "Saved categories" : "This month's categories") {
                if displayedCategories.isEmpty { Text("No categories used this month. Record or import transactions to get started.").foregroundStyle(.secondary) }
                ForEach(displayedCategories) { category in
                    // Spending follows the selected month and this category's currency, independently of its limit.
                    let spent = store.data.entries(in: store.month).filter {
                        $0.categoryID == category.id && $0.kind == .expense && !$0.isTransfer && store.data.currency($0.accountID) == category.currency
                    }.reduce(0) { $0 + $1.amount }
                    VStack(alignment: .leading, spacing: 8) {
                        Button { editing = category } label: {
                            // Match emoji rendering in the budget cards and category editor.
                            Label { Text(category.name + " · " + category.currency) } icon: { SymbolGlyph(symbol: category.symbol) }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.borderless).accessibilityIdentifier("categories.edit." + category.name)
                        Text("\(counts[category.id, default: 0]) transactions this month · Spent \(store.format(spent, currency: category.currency))")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("categories.spent." + category.name)
                        Text(category.limit > 0 ? "Monthly limit \(store.format(category.limit, currency: category.currency))" : "Monthly limit not set")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(store.budgetPlan.note(for: category)).font(.caption).foregroundStyle(.secondary)
                        Button { merging = category } label: {
                            Text("Merge into another category").font(.caption)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.borderless).accessibilityIdentifier("categories.merge." + category.name)
                    }.buttonStyle(.borderless)
                }
                Button("Create category") { creating = true }
            }
        }.navigationTitle("Manage Categories")
            .sheet(item: $editing) { CategoryEditor(existing: $0) }
            .sheet(isPresented: $creating) { CategoryEditor() }
            .sheet(item: $merging) { CategoryMergeScreen(source: $0) }
            .sheet(item: $plan) { preview($0) }
            .onChange(of: store.month) { _, _ in
                // Month navigation always returns to actual usage, not the saved-category override.
                showSaved = false
                work?.cancel()
                workID = UUID()
                busy = false
                plan = nil
            }
            .onDisappear { work?.cancel(); workID = UUID(); busy = false }
    }
    private func prepareCleanup() {
        let snapshot = store.data
        let request = UUID()
        workID = request
        busy = true
        work = Task {
            do {
                // Building/validating a preview must not block scrolling or month navigation.
                let next = try await Task.detached(priority: .userInitiated) {
                    var next = snapshot
                    try next.organizeCategories()
                    return next
                }.value
                try Task.checkCancellation()
                guard workID == request else { return }
                plan = CategoryPlan(original: snapshot, next: next, detail: "Merge equivalent labels and remove unused categories with no budget. Keep custom names, referenced categories, and budget totals. Account balances and transaction amounts stay the same.")
            } catch is CancellationError { }
            catch { if workID == request { store.error = error.localizedDescription } }
            if workID == request { busy = false }
        }
    }
    private func prepareSuggestions() {
        let snapshot = store.data
        let month = store.month
        let request = UUID()
        workID = request
        busy = true
        work = Task {
            do {
                var next = snapshot
                var count = 0
                var cleared = 0
                // Per-account context prevents one account's merchant preference leaking into another currency.
                for account in snapshot.accounts {
                    // Categorise the selected month only; manual corrections and reviewed history remain authoritative.
                    let entries = snapshot.entries(in: month).filter { $0.accountID == account.id && $0.needsReview && !$0.isTransfer && $0.categoryManuallySet != true }
                    let rows = entries.map { ImportRow(id: $0.id, date: $0.date, merchant: $0.merchant, amount: $0.amount, kind: $0.kind, category: snapshot.category($0.categoryID)?.name ?? "Other", note: "", currencyCode: account.currency) }
                    let prepared = try await Categorization.prepare(rows, in: snapshot, accountID: account.id, currency: account.currency)
                    for row in prepared where row.categoryReason != nil {
                        guard let index = next.transactions.firstIndex(where: { $0.id == row.id }) else { continue }
                        var category = row.suggestedCategoryID.flatMap { next.category($0) } ?? Categorization.existing(row.category, in: next, currency: account.currency)
                        if category == nil {
                            category = Category(name: row.category, symbol: CategoryCatalog.symbol(row.category), limit: 0, importKey: CategoryCatalog.key(row.category), currencyCode: account.currency)
                            next.categories.append(category!)
                        }
                        if next.transactions[index].categoryID != category!.id { next.transactions[index].categoryID = category!.id; count += 1 }
                        // Only clear supported decisions; transfer ambiguities remain in the review inbox.
                        if Categorization.isClear(row, in: snapshot, accountID: account.id, currency: account.currency) {
                            next.transactions[index].needsReview = false
                            next.transactions[index].automaticallyReviewed = true
                            cleared += 1
                        }
                    }
                }
                try Task.checkCancellation()
                try next.validate()
                guard workID == request else { return }
                plan = CategoryPlan(original: snapshot, next: next, detail: "\(count) transactions have category changes. \(cleared) clear transactions no longer need review. Uncertain transactions and transfers remain flagged. Amounts, dates, directions, and transfer links stay the same.")
            } catch is CancellationError { }
            catch { if workID == request { store.error = error.localizedDescription } }
            if workID == request { busy = false }
        }
    }
    private func preview(_ candidate: CategoryPlan) -> some View {
        NavigationStack {
            List {
                Section {
                    Text(candidate.detail)
                    LabeledContent("Categories", value: "\(candidate.original.categories.count) → \(candidate.next.categories.count)")
                }
                Section("Transaction changes") {
                    // Include approval-only changes so the user can inspect every flag being cleared.
                    let changes = candidate.next.transactions.filter { item in
                        guard let original = candidate.original.transactions.first(where: { $0.id == item.id }) else { return false }
                        return original.categoryID != item.categoryID || original.needsReview != item.needsReview
                    }
                    if changes.isEmpty { Text("No transaction categories or review flags change.") }
                    ForEach(changes) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.merchant)
                            Text("\(candidate.original.category(candidate.original.transactions.first { $0.id == entry.id }!.categoryID)?.name ?? "Other") → \(candidate.next.category(entry.categoryID)?.name ?? "Other")").font(.caption)
                            if !entry.needsReview { Text("Clear · No review needed").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section("Categories after applying") {
                    ForEach(candidate.next.categories) { category in
                        LabeledContent(category.name + " · " + category.currency, value: store.format(category.limit, currency: category.currency))
                    }
                }
                Button("Apply category changes") {
                    // A background lock, import, or edit invalidates this preview rather than overwriting newer data.
                    guard store.data == candidate.original else { store.error = "Your records changed. Close this preview and check again."; return }
                    if store.update({ $0 = candidate.next }) { plan = nil }
                }.disabled(candidate.original == candidate.next).accessibilityIdentifier("categories.apply")
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Review Categories").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { plan = nil } } }
        }
    }
}
private struct CategoryMergeScreen: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    let source: Category
    @State private var target: UUID?
    @State private var confirming = false
    var body: some View {
        NavigationStack {
            Form {
                // Explain how the merged category retains manual control or recomputes its history estimate.
                Text("Move all \(source.name) transactions and bills into the chosen category and remove \(source.name). If both budgets are automatic, the estimate recalculates from combined history. If either is manual, saved manual limits are added and the result stays manual. Export a backup first if you want to undo this later.")
                Picker("Keep category", selection: $target) {
                    Text("Choose category").tag(nil as UUID?)
                    ForEach(store.data.categories.filter { $0.id != source.id && $0.currency == source.currency }) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("Merge categories") { confirming = true }.disabled(target == nil)
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Merge Categories").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .confirmationDialog("Merge \(source.name) into \(target.flatMap { store.data.category($0)?.name } ?? "selected category")?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Confirm merge", role: .destructive) { if let target, store.update({ try $0.mergeCategory(source.id, into: target) }) { dismiss() } }
                }
        }
    }
}


// Backup material is ephemeral view state and is never written to preferences, logs, or the ledger.
struct BackupScreen: View {
    @EnvironmentObject private var store: HarborStore
    @EnvironmentObject private var lock: HarborLock
    @State private var recoveryKey = ""
    @State private var confirmation = ""
    @State private var restoreKey = ""
    @State private var exportBytes: Data?
    @State private var importBytes: Data?
    @State private var candidate: FinanceData?
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmRestore = false
    @State private var plaintextWarning = false
    @State private var exportType: UTType = .harborBackup
    @State private var status = ""
    @State private var pendingCount: Int?
    var body: some View {
        Form {
            Section("Encrypted portable backup") {
                Text("Keep the recovery key separate from your backup. Harbor cannot recover a lost key.").font(.caption)
                LearnMoreLink(title: "What backups include", paragraphs: ["A backup contains your saved ledger, not device keys, app lock settings, or pending Apple Pay captures. Store its recovery key separately. Harbor cannot recover a forgotten key."])
                Text(pendingCount.map { "Pending capture files excluded: \($0)" } ?? "Pending captures could not be counted. Check the Apple Pay inbox before exporting.").font(.caption)
                if recoveryKey.isEmpty {
                    Button("Create recovery key") { recoveryKey = PortableBackup.recoveryKey(); confirmation = "" }
                        .disabled(store.recoveryNeeded).accessibilityIdentifier("backup.createKey")
                } else {
                    Text(recoveryKey).font(.caption.monospaced()).accessibilityIdentifier("backup.recoveryKey")
                    Button("Copy recovery key") { UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: recoveryKey]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]) }
                    SecureField("Re-enter recovery key", text: $confirmation).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("backup.confirmKey")
                    Button("Export encrypted backup") { exportEncrypted() }
                        .disabled(!keysMatch || store.recoveryNeeded).accessibilityIdentifier("backup.exportEncrypted")
                    Button("Cancel backup", role: .cancel) { clearSecrets() }
                }
            }
            Section("Restore") {
                Button("Choose encrypted or legacy JSON backup") { clearSecrets(); importing = true }
                    .accessibilityIdentifier("backup.chooseRestore")
                if importBytes != nil {
                    SecureField("Recovery key (encrypted backups)", text: $restoreKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("backup.restoreKey")
                    Button("Validate backup") {
                        do {
                            guard let bytes = importBytes else { return }
                            candidate = try PortableBackup.decode(bytes, recoveryKey: restoreKey)
                            restoreKey = ""; importBytes = nil; status = ""; confirmRestore = true
                        } catch { status = error.localizedDescription }
                    }.accessibilityIdentifier("backup.validate")
                    Button("Cancel restore", role: .cancel) { clearSecrets() }
                }
                Text("Restore replaces the ledger only after validation and confirmation. Existing pending captures are held for review in Apple Pay settings.").font(.caption)
            }
            Section("Unencrypted export") {
                Button("Export unencrypted JSON") { plaintextWarning = true }.disabled(store.recoveryNeeded)
                Text("Anyone who can open this file can read your financial records. Use encrypted backups for safekeeping.").font(.caption)
            }
            if !status.isEmpty { Section { Text(status).accessibilityIdentifier("backup.status") } }
        }.navigationTitle("Backups and recovery")
            .onAppear { refreshCount() }
            .onDisappear { clearSecrets() }
            // Popover-style confirmations may cancel by tapping outside rather than a Cancel button.
            .onChange(of: confirmRestore) { _, presented in if !presented { clearSecrets() } }
            .onChange(of: lock.unlocked) { _, unlocked in if !unlocked { clearSecrets() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in clearSecrets() }
            .fileExporter(isPresented: $exporting, document: exportBytes.map { HarborDocument(bytes: $0) }, contentType: exportType, defaultFilename: exportType == .json ? "Harbor-unencrypted.json" : "Harbor-backup.harborbackup") { result in
                switch result { case .success: status = "Backup exported. Keep the recovery key separately if encrypted."
                case .failure(let error): status = error.localizedDescription }
                clearSecrets()
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.harborBackup, .data, .json]) { result in
                guard lock.unlocked, UIApplication.shared.isProtectedDataAvailable else { clearSecrets(); return }
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    // Bound allocation even when a file provider cannot supply an accurate size.
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    let bytes = try handle.read(upToCount: PortableBackup.maximumBytes + 1) ?? Data()
                    guard bytes.count <= PortableBackup.maximumBytes else { throw FinanceError(message: "Backup is too large.") }
                    importBytes = bytes; status = "Backup selected. Enter its key if encrypted, then validate."
                } catch { clearSecrets(); status = error.localizedDescription }
            }
            .confirmationDialog("Replace current ledger?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Replace records", role: .destructive) {
                    do {
                        guard let candidate else { return }
                        try store.restore(JSONEncoder().encode(candidate))
                        status = "Backup restored. Review held Apple Pay captures in Settings."
                    } catch { status = error.localizedDescription }
                    clearSecrets(); refreshCount()
                }
                Button("Cancel", role: .cancel) { clearSecrets() }
            } message: {
                Text(candidate.map { "\($0.accounts.count) accounts · \($0.transactions.count) transactions · \($0.categories.count) categories · \($0.goals.count) goals · \($0.bills.count) bills. Existing records will be replaced." } ?? "")
            }
            .confirmationDialog("Export readable financial data?", isPresented: $plaintextWarning, titleVisibility: .visible) {
                Button("Export unencrypted JSON", role: .destructive) {
                    do { try store.data.validate(); exportBytes = try JSONEncoder().encode(store.data); exportType = .json; exporting = true }
                    catch { status = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) { clearSecrets() }
            }
    }
    private var keysMatch: Bool {
        guard let original = try? PortableBackup.key(recoveryKey), let entered = try? PortableBackup.key(confirmation) else { return false }
        return original == entered
    }
    private func exportEncrypted() {
        do {
            exportBytes = try PortableBackup.encrypt(store.data, recoveryKey: recoveryKey)
            exportType = .harborBackup; exporting = true
        } catch { status = error.localizedDescription }
    }
    private func refreshCount() {
        // Count ciphertext filenames without requiring capture to be enabled or exposing purchase details.
        do {
            let folder = ApplePayCaptureService.folder
            guard FileManager.default.fileExists(atPath: folder.path) else { pendingCount = 0; return }
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            let held = FileManager.default.fileExists(atPath: ApplePayCaptureService.quarantine.path)
                ? try FileManager.default.contentsOfDirectory(at: ApplePayCaptureService.quarantine, includingPropertiesForKeys: nil) : []
            pendingCount = (files + held).filter { $0.pathExtension == "encrypted" }.count
        } catch { pendingCount = nil }
    }
    private func clearSecrets() {
        recoveryKey = ""; confirmation = ""; restoreKey = ""; exportBytes = nil; importBytes = nil; candidate = nil
        exporting = false; confirmRestore = false
    }
}
