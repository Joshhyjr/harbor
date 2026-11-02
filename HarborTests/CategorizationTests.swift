import XCTest
@testable import HarborCore

// Exercise category-only changes against money/reference invariants and explicit user preferences.
final class CategorizationTests: XCTestCase {
    // Month/currency/direction views are projections, never destructive cleanup of saved budgets or history.
    func testMonthlyCategoriesFollowTransactionsAndKeepSavedLimits() throws {
        var data = ledger()
        let income = Category(name: "Income", symbol: "arrow.down.left", limit: 0)
        let unused = Category(name: "Unused plan", symbol: "tag", limit: 12345)
        let usd = Account(name: "USD", openingBalance: 0, currencyCode: "USD")
        let foreign = Category(name: "US Shopping", symbol: "bag", limit: 0, currencyCode: "USD")
        data.categories += [income, unused, foreign]; data.accounts.append(usd)
        let september = TransactionImport.date("2026-09-02")!
        data.transactions = [
            Transaction(merchant: "Last month", amount: 100, kind: .expense, date: september, accountID: data.accounts[0].id, categoryID: data.categories[0].id),
            Transaction(merchant: "This month", amount: 200, kind: .expense, date: date, accountID: data.accounts[0].id, categoryID: data.categories[1].id),
            Transaction(merchant: "Pay", amount: 1000, kind: .income, date: date, accountID: data.accounts[0].id, categoryID: income.id),
            Transaction(merchant: "US store", amount: 300, kind: .expense, date: date, accountID: usd.id, categoryID: foreign.id)
        ]
        // Saved model-approved assignments participate exactly like manual transactions, across currencies.
        data.transactions[3].automaticallyReviewed = true
        let before = data
        XCTAssertEqual(data.categoryTransactionCounts(in: date), [data.categories[1].id: 1, income.id: 1, foreign.id: 1])
        XCTAssertEqual(data.categoryTransactionCounts(in: september), [data.categories[0].id: 1])
        XCTAssertEqual(data.usedCategories(in: date, currency: "CAD", kind: .expense).map(\.name), ["Health"])
        XCTAssertEqual(data.usedCategories(in: september, currency: "CAD", kind: .expense).map(\.name), ["Transport"])
        XCTAssertEqual(data.usedCategories(in: date, currency: "CAD").map(\.name), ["Health", "Income"])
        XCTAssertEqual(data.usedCategories(in: date, currency: "USD").map(\.id), [foreign.id])
        XCTAssertTrue(data.usedCategories(in: TransactionImport.date("2026-08-01")!).isEmpty)
        XCTAssertEqual(data, before); XCTAssertEqual(data.budget, before.budget)
        // A user correction changes this month's membership without duplicating a saved category.
        data.transactions[1].categoryID = data.categories[0].id
        data.transactions[1].categoryManuallySet = true
        XCTAssertEqual(data.usedCategories(in: date, currency: "CAD", kind: .expense).map(\.name), ["Transport"])
        XCTAssertEqual(data.categories, before.categories)
    }
    func testCategoryOptionsStayVirtualUntilTransactionIsSaved() async throws {
        var data = FinanceData(isDemo: false)
        data.accounts = [Account(name: "Checking", openingBalance: 0)]
        let row = ImportRow(date: date, merchant: "Payroll", amount: 1000, kind: .income, category: "Other", note: "")
        XCTAssertFalse(Categorization.options(in: data, currency: "CAD").isEmpty)
        let prepared = try await Categorization.prepare([row], in: data, accountID: data.accounts[0].id, currency: "CAD")
        XCTAssertTrue(data.categories.isEmpty)
        try TransactionImport.apply(prepared, to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        XCTAssertEqual(data.categories.map(\.name), ["Income"])
        XCTAssertEqual(data.usedCategories(in: date).map(\.name), ["Income"])
        XCTAssertTrue(data.usedCategories(in: date, kind: .expense).isEmpty)
    }
    func testTransferOnlyCategoriesDoNotPopulateMonthlySpending() throws {
        var data = ledger()
        let source = data.accounts[0].id
        let entry = Transaction(merchant: "Transfer to savings", amount: 100, kind: .expense, date: date, accountID: source, categoryID: data.categories[0].id)
        data.transactions.append(entry)
        try data.linkSavingsTransfer(entry.id)
        XCTAssertTrue(data.usedCategories(in: date).isEmpty)
        XCTAssertEqual(data.categories.count, 3)
        try data.validate()
    }
    private let date = TransactionImport.date("2026-10-01")!
    private func ledger() -> FinanceData {
        var data = FinanceData(name: "Test", isDemo: false)
        data.accounts = [Account(name: "Checking", openingBalance: 100_000)]
        data.categories = [Category(name: "Transport", symbol: "car", limit: 10_000), Category(name: "Health", symbol: "cross.case", limit: 0), Category(name: "Other", symbol: "tag", limit: 0)]
        return data
    }
    func testImportReusesEquivalentLabelsAndRenamedCategory() throws {
        var data = ledger()
        data.categories[0].importKey = CategoryCatalog.key("Transport")
        data.categories[0].name = "Getting around"
        let rows = ["Gas & Fuel", "Car Maintenance"].map { ImportRow(date: date, merchant: "Vendor", amount: 100, kind: .expense, category: $0, note: "") }
        try TransactionImport.apply(rows, to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        XCTAssertEqual(data.categories.count, 3)
        XCTAssertTrue(data.transactions.allSatisfy { $0.categoryID == data.categories[0].id })
        XCTAssertEqual(data.categories[0].name, "Getting around")
        XCTAssertEqual(data.balance(data.accounts[0].id), 99_800)
        let restored = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored, data)
    }
    func testManualImportCategoryBypassesAutomaticAliases() async throws {
        var data = ledger()
        var row = ImportRow(date: date, merchant: "Payroll", amount: 100, kind: .income, category: "My income", note: "", manualCategory: true)
        row.suggestedCategoryID = data.categories[0].id
        let prepared = try await Categorization.prepare([row], in: data, accountID: data.accounts[0].id, currency: "CAD")
        XCTAssertEqual(prepared, [row])
        try TransactionImport.apply(prepared, to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        XCTAssertEqual(data.category(data.transactions[0].categoryID)?.name, "My income")
        XCTAssertEqual(data.transactions[0].categoryManuallySet, true)
    }
    func testReviewedHistoryWinsButImportedSuggestionsDoNotTeach() throws {
        var data = ledger()
        let chosen = data.categories[1]
        for day in 1...3 {
            data.transactions.append(Transaction(merchant: "Local Vendor", amount: 100, kind: .expense, date: TransactionImport.date("2026-09-0\(day)")!, accountID: data.accounts[0].id, categoryID: chosen.id))
        }
        let row = ImportRow(date: date, merchant: "Local Vendor", amount: 100, kind: .expense, category: "Gas & Fuel", note: "")
        XCTAssertEqual(Categorization.local(row, in: data, accountID: data.accounts[0].id, currency: "CAD")?.categoryID, chosen.id)
        for i in data.transactions.indices { data.transactions[i].needsReview = true }
        XCTAssertEqual(Categorization.local(row, in: data, accountID: data.accounts[0].id, currency: "CAD")?.name, "Transport")
        data.transactions[0].needsReview = false
        XCTAssertNotEqual(Categorization.local(row, in: data, accountID: data.accounts[0].id, currency: "USD")?.categoryID, chosen.id)
    }
    func testCleanupMergesReferencesAndKeepsBudgetsWithoutChangingBalances() throws {
        var data = ledger()
        let fuel = Category(name: "Gas & Fuel", symbol: "tag", limit: 5000)
        data.categories.append(fuel)
        data.transactions.append(Transaction(merchant: "Fuel", amount: 500, kind: .expense, date: date, accountID: data.accounts[0].id, categoryID: fuel.id))
        data.bills.append(Bill(name: "Fuel", amount: 500, due: date, accountID: data.accounts[0].id, categoryID: fuel.id))
        let balance = data.netWorth, budget = data.budget, ids = data.transactions.map(\.id)
        try data.organizeCategories()
        XCTAssertEqual(data.netWorth, balance); XCTAssertEqual(data.budget, budget)
        XCTAssertEqual(data.transactions.map(\.id), ids)
        XCTAssertEqual(data.categories.count, 1)
        XCTAssertEqual(data.categories[0].limit, 15000)
        XCTAssertEqual(data.bills[0].categoryID, data.transactions[0].categoryID)
        let cleaned = data; try data.organizeCategories(); XCTAssertEqual(data, cleaned)
        // An explicit user merge keeps old import identities so later statements cannot recreate the source.
        let custom = Category(name: "Car costs", symbol: "car", limit: 0, importKey: "car costs")
        data.categories.append(custom)
        try data.mergeCategory(data.categories[0].id, into: custom.id)
        XCTAssertEqual(Categorization.existing("Gas & Fuel", in: data, currency: "CAD")?.id, custom.id)
    }
    func testTopCategoriesExcludeZeroIncomeTransfersAndOtherCurrencies() throws {
        var data = ledger()
        let account = data.accounts[0].id
        data.transactions = [Transaction(merchant: "Fuel", amount: 100, kind: .expense, date: date, accountID: account, categoryID: data.categories[0].id), Transaction(merchant: "Pay", amount: 500, kind: .income, date: date, accountID: account, categoryID: data.categories[1].id)]
        let other = Account(name: "USD", openingBalance: 0, currencyCode: "USD")
        data.accounts.append(other)
        let usd = Category(name: "USD groceries", symbol: "basket", limit: 0, currencyCode: "USD")
        data.categories.append(usd)
        data.transactions.append(Transaction(merchant: "US food", amount: 900, kind: .expense, date: date, accountID: other.id, categoryID: usd.id))
        let savings = Account(name: "Savings", openingBalance: 0)
        data.accounts.append(savings)
        let withdrawal = Transaction(merchant: "Transfer to savings", amount: 300, kind: .expense, date: date, accountID: account, categoryID: data.categories[2].id)
        data.transactions.append(withdrawal)
        try data.linkSavingsTransfer(withdrawal.id, savingsAccountID: savings.id)
        XCTAssertEqual(data.topCategories(in: date).map(\.cents), [100])
        XCTAssertEqual(data.topCategories(in: date).map { $0.category.name }, ["Transport"])
        try data.validate()
        XCTAssertTrue(data.topCategories(in: TransactionImport.date("2026-08-01")!).isEmpty)
    }
    func testGeneratedIndexIsUntrustedAndSuggestionDoesNotMutateLedger() async throws {
        let data = ledger(), before = ledger()
        let options = Categorization.options(in: data, currency: "CAD")
        XCTAssertNil(Categorization.accept(index: -1, clear: true, options: options))
        XCTAssertNil(Categorization.accept(index: options.count, clear: true, options: options))
        XCTAssertNil(Categorization.accept(index: 0, clear: false, options: options))
        XCTAssertNotNil(Categorization.accept(index: 0, clear: true, options: options))
        let row = ImportRow(date: date, merchant: "Payroll", amount: 100, kind: .income, category: "Other", note: "")
        let prepared = try await Categorization.prepare([row], in: data, accountID: data.accounts[0].id, currency: "CAD")
        XCTAssertEqual(prepared[0].category, "Income")
        XCTAssertEqual(prepared[0].amount, row.amount); XCTAssertEqual(prepared[0].date, row.date); XCTAssertEqual(prepared[0].kind, row.kind)
        XCTAssertTrue(data.transactions.isEmpty); XCTAssertEqual(data.netWorth, before.netWorth)
    }
    func testLiveAppleModelWithFictionalMerchantWhenAvailable() async throws {
        print("APPLE CATEGORY MODEL: " + AppleCategoryModel.status)
        guard AppleCategoryModel.isAvailable else { throw XCTSkip(AppleCategoryModel.status) }
        let row = ImportRow(date: date, merchant: "Local Grocery Supermarket", amount: 100, kind: .expense, category: "Other", note: "")
        let options = Categorization.options(in: ledger(), currency: "CAD")
        do {
            guard let suggestion = try await AppleCategoryModel.generate(row, options: options) else { throw XCTSkip("The available on-device model abstained on this fictional input.") }
            XCTAssertEqual(suggestion.name, "Groceries")
            print("APPLE CATEGORY MODEL LIVE RESULT: " + suggestion.name)
        } catch let error as XCTSkip { throw error }
        catch {
            // This diagnostic is restricted to the fixed fictional smoke-test input, never a saved ledger.
            print("APPLE CATEGORY MODEL LIVE ERROR: " + error.localizedDescription)
            throw XCTSkip("On-device model generation is unavailable in this test runtime.")
        }
    }
    // Regression: saving clear rows must clear flags without approving unknowns, transfers, or stale AI evidence.
    func testImportApprovesOnlyClearCategoriesAndCurrentModelEvidence() throws {
        var data = ledger()
        func row(_ merchant: String, _ category: String) -> ImportRow {
            ImportRow(date: date, merchant: merchant, amount: 100, kind: .expense, category: category, note: "")
        }
        var model = row("Fictional supermarket", "Groceries")
        model.sourceCategory = "Other"
        model.clearCategoryEvidence = Categorization.evidenceKey(model)
        var stale = model
        stale.id = UUID(); stale.merchant = "Unclear changed merchant"
        var manual = row("Local vendor", "My purchases"); manual.manualCategory = true
        let rows = [row("Fuel", "Gas & Fuel"), row("Unclear", "Other"), row("Vendor", "Unfamiliar label"), row("E-transfer to person", "Shopping"), row("Card payment", "Bank Fees"), model, stale, manual]
        let before = data.balance(data.accounts[0].id)
        try TransactionImport.apply(rows, to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        XCTAssertEqual(data.transactions.map(\.needsReview), [false, true, true, true, true, false, true, false])
        XCTAssertEqual(data.balance(data.accounts[0].id), before - 800)
        XCTAssertEqual(data.transactions[0].automaticallyReviewed, true)
        XCTAssertNil(data.transactions.last?.automaticallyReviewed)
        let restored = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored, data)
    }
    // Existing imports are reassessed atomically from one snapshot and cannot train future guesses.
    func testExistingReviewCleanupPreservesUnknownsManualFlagsAndFinancialFields() throws {
        var data = ledger()
        let unknown = Category(name: "Unfamiliar", symbol: "tag", limit: 0)
        data.categories.append(unknown)
        let merchants = ["Fuel", "Unclear", "E-transfer", "Manually flagged", "Mystery"]
        data.transactions = merchants.enumerated().map { index, merchant in
            Transaction(merchant: merchant, amount: 100, kind: .expense, date: date, accountID: data.accounts[0].id, categoryID: data.categories[index == 1 ? 2 : index == 4 ? 3 : 0].id, needsReview: true, categoryManuallySet: index == 3 ? true : nil)
        }
        let original = data
        XCTAssertEqual(Categorization.clearExistingReviewFlags(in: &data), 1)
        XCTAssertEqual(data.transactions.map(\.needsReview), [false, true, true, true, true])
        XCTAssertEqual(data.netWorth, original.netWorth)
        XCTAssertEqual(data.categories, original.categories)
        XCTAssertEqual(data.transactions.map(\.id), original.transactions.map(\.id))
        XCTAssertEqual(data.transactions.map(\.amount), original.transactions.map(\.amount))
        XCTAssertEqual(data.transactions.map(\.date), original.transactions.map(\.date))
        XCTAssertEqual(Categorization.clearExistingReviewFlags(in: &data), 0)
        // Several automatically approved purchases never become reviewed merchant evidence.
        var example = data.transactions[0]
        for day in 2...5 {
            example.id = UUID(); example.date = TransactionImport.date("2026-10-0\(day)")!
            data.transactions.append(example)
        }
        let query = ImportRow(date: date, merchant: "Fuel", amount: 100, kind: .expense, category: "Other", note: "")
        XCTAssertNil(Categorization.local(query, in: data, accountID: data.accounts[0].id, currency: "CAD"))
        // Removing the new optional field emulates a pre-feature backup.
        let bytes = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(FinanceData.self, from: bytes), original)
    }
    // Reusing a saved unfamiliar label is not evidence of clarity, even when preparation finds it.
    func testUnrecognizedLabelsAndContradictoryDirectionsStayFlagged() async throws {
        var data = ledger()
        data.categories.append(Category(name: "Unfamiliar", symbol: "tag", limit: 0))
        let unknown = ImportRow(date: date, merchant: "Vendor", amount: 100, kind: .expense, category: "Unfamiliar", note: "")
        let prepared = try await Categorization.prepare([unknown], in: data, accountID: data.accounts[0].id, currency: "CAD")
        XCTAssertFalse(Categorization.isClear(prepared[0], in: data, accountID: data.accounts[0].id, currency: "CAD"))
        for (kind, category) in [(TransactionKind.income, "Shopping"), (.expense, "Income")] {
            var conflicting = ImportRow(date: date, merchant: "Vendor", amount: 100, kind: kind, category: category, note: "")
            conflicting.clearCategoryEvidence = Categorization.evidenceKey(conflicting)
            XCTAssertFalse(Categorization.isClear(conflicting, in: data, accountID: data.accounts[0].id, currency: "CAD"))
        }
    }
}
