import SwiftUI

// History is an immutable receipt of each completed import, independent of later transaction edits.
struct ImportHistoryScreen: View {
    @EnvironmentObject var store: HarborStore
    var body: some View {
        List {
            Section {
                Text("History starts with imports saved in this version. Earlier transactions remain in Activity.").font(.caption)
            }
            if (store.data.statementImports ?? []).isEmpty {
                Text("No imports recorded yet").accessibilityIdentifier("importHistory.empty")
            }
            ForEach((store.data.statementImports ?? []).sorted { $0.importedAt > $1.importedAt }) { receipt in
                NavigationLink { ImportReceiptScreen(receipt: receipt) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(receipt.filename).font(.headline)
                        Text("\(receipt.accountName) · \(receipt.currency) · \(receipt.importedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                        Text("\(receipt.addedRows) added · \(receipt.matchedRows) matched · \(receipt.duplicatesSkipped) duplicates skipped").font(.caption)
                    }
                }.accessibilityIdentifier("importHistory.receipt." + receipt.id.uuidString)
            }
        }.navigationTitle("Import history")
    }
}

private struct ImportReceiptScreen: View {
    @EnvironmentObject var store: HarborStore
    let receipt: StatementImportRecord
    private var ids: Set<UUID> { Set(receipt.addedTransactionIDs + receipt.matchedTransactionIDs) }
    var body: some View {
        List {
            Section("Source") {
                Text(receipt.filename).accessibilityIdentifier("importHistory.filename")
                LabeledContent("Account at import", value: receipt.accountName)
                LabeledContent("Currency", value: receipt.currency)
                LabeledContent("Imported", value: receipt.importedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Transaction dates", value: "\(receipt.firstDate.formatted(date: .abbreviated, time: .omitted)) – \(receipt.lastDate.formatted(date: .abbreviated, time: .omitted))")
            }
            Section("Rows") {
                count("In file", receipt.totalRows, id: "total")
                count("Added", receipt.addedRows, id: "added")
                count("Matched Apple Pay purchases", receipt.matchedRows, id: "matched")
                count("Duplicates skipped", receipt.duplicatesSkipped, id: "duplicates")
                count("Other rows left unchecked", receipt.deselectedRows, id: "deselected")
                Text("A linked savings transfer can create two ledger entries from one imported row.").font(.caption)
            }
            Section("Saved entries") {
                let remaining = store.data.transactions.filter { ids.contains($0.id) }.count
                LabeledContent("Entries still in ledger", value: "\(remaining) of \(ids.count)")
                Text("Later edits and deletions do not rewrite this import receipt.").font(.caption)
                NavigationLink("View imported transactions") {
                    StatementEntriesScreen(title: "Imported transactions", ids: ids)
                }.disabled(remaining == 0)
            }
            Section("Statement balances") {
                if let opening = receipt.openingBalance { LabeledContent("Opening balance", value: store.format(opening, currency: receipt.currency)) }
                if let closing = receipt.closingBalance { LabeledContent("Closing balance", value: store.format(closing, currency: receipt.currency)) }
                if receipt.closingBalance == nil { Text("This file did not supply a closing balance. You can enter one from your statement.").font(.caption) }
                Text("Confirm the closing date from your statement; the last transaction date may differ.").font(.caption)
                if store.data.accounts.contains(where: { $0.id == receipt.accountID && $0.currency == receipt.currency }) {
                    NavigationLink("Compare account balance") {
                        MonthlyReconciliationScreen(accountID: receipt.accountID, closingDate: receipt.lastDate, statementBalance: receipt.closingBalance)
                    }.accessibilityIdentifier("importHistory.compare")
                } else { Text("The original account is no longer available. This receipt is kept for reference.").font(.caption) }
            }
        }.navigationTitle("Import details")
    }
    private func count(_ title: String, _ value: Int, id: String) -> some View {
        LabeledContent(title, value: String(value)).accessibilityIdentifier("importHistory." + id).accessibilityValue(String(value))
    }
}

struct MonthlyReconciliationScreen: View {
    @EnvironmentObject var store: HarborStore
    @State private var accountID: UUID?
    @State private var closingDate: Date
    @State private var balanceText: String
    @State private var status = ""
    @FocusState private var balanceFocused: Bool
    init(accountID: UUID? = nil, closingDate: Date? = nil, statementBalance: Int? = nil) {
        _accountID = State(initialValue: accountID)
        let start = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        _closingDate = State(initialValue: closingDate ?? Calendar.current.date(byAdding: .day, value: -1, to: start) ?? start)
        _balanceText = State(initialValue: statementBalance.map(Money.input) ?? "")
    }
    private var account: Account? { store.data.accounts.first { $0.id == accountID } }
    private var check: StatementBalanceCheck? {
        guard let account, let balance = Money.parse(balanceText, allowNegative: true), abs(balance) <= 100_000_000_00 else { return nil }
        return StatementBalanceCheck(accountID: account.id, accountName: account.name, currency: account.currency,
                                     closingDay: StatementReconciliation.day(closingDate), statementBalance: balance)
    }
    private var result: StatementReconciliation.Result? {
        check.flatMap { try? StatementReconciliation.calculate($0, in: store.data) }
    }
    var body: some View {
        List {
            Section("Statement") {
                Picker("Account", selection: $accountID) {
                    Text("Choose account").tag(nil as UUID?)
                    ForEach(store.data.accounts) { Text("\($0.name) · \($0.currency)").tag(Optional($0.id)) }
                }.accessibilityIdentifier("reconciliation.account")
                DatePicker("Statement closing date", selection: $closingDate, displayedComponents: .date)
                    .accessibilityIdentifier("reconciliation.date")
                TextField("Closing balance (\(account?.currency ?? "account currency"))", text: $balanceText)
                    .keyboardType(.numbersAndPunctuation).focused($balanceFocused).submitLabel(.done)
                    .onSubmit { balanceFocused = false }.accessibilityIdentifier("reconciliation.statementBalance")
                Text("Enter the statement's closing balance in this account's currency. Debt is negative in Harbor; use the same sign convention.").font(.caption)
            }
            if let result, let account {
                comparison(result, account: account)
                Section("Review") {
                    Text("Check pending purchases, missing history, and your opening balance when totals differ.").font(.caption)
                    LearnMoreLink(title: "How balances are compared", paragraphs: [
                        "Opening balance is treated as the balance before your recorded transactions. All account movements through the closing day are included, including linked transfers. Later transactions are excluded.",
                        "Check the closing date on your statement. It may differ from the last transaction date suggested by an import receipt. Use the same currency and sign convention; debt is negative in Harbor.",
                        "Equal balances do not prove every transaction matches. Unconfirmed Apple Pay purchases remain available for review. Saving a comparison never changes your opening balance or transactions."
                    ])
                    LabeledContent("Unconfirmed Apple Pay", value: String(result.provisional.count))
                        .accessibilityIdentifier("reconciliation.provisionalCount")
                    NavigationLink("Review unconfirmed purchases") {
                        StatementEntriesScreen(title: "Unconfirmed purchases", ids: Set(result.provisional.map(\.id)))
                    }.disabled(result.provisional.isEmpty)
                    NavigationLink("Review transactions in closing month") {
                        StatementEntriesScreen(title: "Closing month", ids: Set(result.entries.filter { Calendar.current.isDate($0.date, equalTo: closingDate, toGranularity: .month) }.map(\.id)))
                    }
                }
                Section {
                    Button("Save comparison") {
                        // Dismiss the input keyboard so the saved result and confirmation remain visible.
                        balanceFocused = false
                        if let check, store.update({ try $0.saveStatementCheck(check) }) { status = "Statement comparison saved. Balances will be checked against your current ledger when reopened." }
                    }.disabled(store.recoveryNeeded).accessibilityIdentifier("reconciliation.save")
                }
            } else {
                Text(store.data.accounts.isEmpty ? "Add an account before comparing a statement." : "Choose an account and enter a valid closing balance to compare.").font(.caption)
            }
            if !status.isEmpty { Text(status).font(.caption).accessibilityIdentifier("reconciliation.status") }
            savedChecks
        }.navigationTitle("Monthly reconciliation").scrollDismissesKeyboard(.interactively)
            .onAppear {
                if accountID == nil {
                    // Reopen the last compared available account so its saved statements are easy to find.
                    accountID = store.data.mostRecentStatementAccountID ?? store.data.accounts.first?.id
                }
            }
            .onChange(of: accountID) { _, _ in balanceText = ""; status = "" }
            .onChange(of: closingDate) { _, _ in status = "" }
            .onChange(of: balanceText) { _, _ in status = "" }
    }
    private func comparison(_ result: StatementReconciliation.Result, account: Account) -> some View {
        Section("Balance at close") {
            LabeledContent("Harbor balance", value: store.format(result.ledgerBalance, currency: account.currency))
                .accessibilityIdentifier("reconciliation.ledgerBalance")
            LabeledContent("Statement balance", value: store.format(result.statementBalance, currency: account.currency))
            LabeledContent("Harbor minus statement", value: store.format(result.difference, currency: account.currency))
                .accessibilityIdentifier("reconciliation.difference").accessibilityValue(store.format(result.difference, currency: account.currency))
            Text(result.difference == 0 ? "Balances match" : "Balances differ")
                .foregroundStyle(result.difference == 0 ? HarborStyle.teal : .orange)
                .accessibilityIdentifier("reconciliation.result")
            Text("Includes all account movements through this closing day, including linked transfers. Later transactions are excluded.").font(.caption)
        }
    }
    @ViewBuilder private var savedChecks: some View {
        let checks = (store.data.statementBalanceChecks ?? []).filter { $0.accountID == accountID }.sorted { $0.closingDay > $1.closingDay }
        if !checks.isEmpty {
            Section("Saved comparisons") {
                ForEach(checks) { saved in
                    Button {
                        if let date = TransactionImport.date(saved.closingDay) {
                            closingDate = date; balanceText = Money.input(saved.statementBalance); status = ""
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(saved.closingDay + " · " + store.format(saved.statementBalance, currency: saved.currency))
                            if let current = try? StatementReconciliation.calculate(saved, in: store.data) {
                                Text(current.difference == 0 ? "Matches current ledger" : "Current difference: " + store.format(current.difference, currency: saved.currency)).font(.caption)
                            }
                        }
                    }.disabled(saved.currency != account?.currency).accessibilityIdentifier("reconciliation.saved." + saved.closingDay)
                }
            }
        }
    }
}

// Both receipt and reconciliation drill-downs open the normal editor, retaining existing correction rules.
private struct StatementEntriesScreen: View {
    @EnvironmentObject var store: HarborStore
    let title: String
    let ids: Set<UUID>
    @State private var editing: Transaction?
    var body: some View {
        List {
            let entries = store.data.transactions.filter { ids.contains($0.id) }.sorted { $0.date > $1.date }
            if entries.isEmpty { Text("No saved entries to show") }
            ForEach(entries) { entry in
                Button { editing = entry } label: { LedgerRow(transaction: entry) }.buttonStyle(.plain)
            }
        }.navigationTitle(title).sheet(item: $editing) { TransactionEditor(existing: $0) }
    }
}
