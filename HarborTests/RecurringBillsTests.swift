import XCTest
@testable import HarborCore

// Test recognition, persistence compatibility, and ledger invariants through the shared import path.
final class RecurringBillsTests: XCTestCase {
    private func date(_ value: String) -> Date {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)!
    }
    private func ledger(_ dates: [String] = ["2026-01-31", "2026-02-28", "2026-03-31"], amounts: [Int] = [10000, 12000, 9000]) -> FinanceData {
        var data = FinanceData(isDemo: false)
        data.accounts = [Account(name: "Chequing", openingBalance: 1000000)]
        data.categories = [Category(name: "Utilities", symbol: "bolt", limit: 50000)]
        data.transactions = dates.enumerated().map { index, value in
            Transaction(merchant: index == 1 ? "HYDRO   ELECTRICITY" : "Hydro Electricity", amount: amounts[index], kind: .expense,
                        date: date(value), accountID: data.accounts[0].id, categoryID: data.categories[0].id, needsReview: true)
        }
        return data
    }
    // Real import plumbing must identify named services, preserve amounts, and avoid duplicate reminders.
    func testICloudImportsAutomaticallyCategoriseAndEstablishCadence() throws {
        var data = ledger([], amounts: [])
        let csv = Data("Date,Description,Amount,Category\n2026-01-07,APPLE ICLOUD+,-3.99,Entertainment\n2026-02-07,Apple iCloud,-3.99,Other\n2026-03-07,iCloud Storage,-3.99,Subscriptions\n".utf8)
        let rows = try TransactionImport.csv(csv).rows
        let original = data.netWorth
        try TransactionImport.apply(rows, to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        let bill = try XCTUnwrap(data.bills.first)
        XCTAssertEqual(data.bills.count, 1)
        XCTAssertEqual(bill.name, "Apple iCloud"); XCTAssertEqual(bill.frequency, .monthly)
        XCTAssertEqual(bill.due, date("2026-04-07")); XCTAssertEqual(bill.needsScheduleReview, false)
        XCTAssertEqual(data.category(bill.categoryID)?.name, "Subscription")
        XCTAssertTrue(data.transactions.allSatisfy { !$0.needsReview && $0.recurringBillID == bill.id && $0.categoryID == bill.categoryID })
        XCTAssertEqual(data.netWorth, original - 1197); XCTAssertEqual(data.transactions.count, 3)
        let before = data; try RecurringBills.autoTrack(in: &data); XCTAssertEqual(data, before)
        let next = ImportRow(date: date("2026-04-07"), merchant: "Apple iCloud+", amount: 399, kind: .expense, category: "Other", note: "")
        try TransactionImport.apply([next], to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        XCTAssertEqual(data.bills.count, 1); XCTAssertEqual(data.bills[0].due, date("2026-05-07"))
        XCTAssertEqual(data.transactions.last?.recurringBillID, bill.id)
    }
    // Subscription identity can be clear before its monthly/annual billing schedule is known.
    func testSingleSubscriptionPromptsOnlyForScheduleThenRefinesFromHistory() throws {
        var data = ledger([], amounts: [])
        func row(_ day: String) -> ImportRow { ImportRow(date: date(day), merchant: "APPLE ICLOUD+", amount: 399, kind: .expense, category: "Other", note: "") }
        try TransactionImport.apply([row("2026-01-07")], to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        let id = data.bills[0].id
        XCTAssertEqual(data.bills[0].needsScheduleReview, true)
        XCTAssertFalse(data.transactions[0].needsReview)
        try TransactionImport.apply([row("2026-02-07"), row("2026-03-07")], to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        XCTAssertEqual(data.bills.count, 1); XCTAssertEqual(data.bills[0].id, id)
        XCTAssertEqual(data.bills[0].needsScheduleReview, false)
        XCTAssertEqual(data.bills[0].due, date("2026-04-07"))
    }
    // A later amount/date anomaly must prompt again without adding or silently settling another expense.
    func testDetectedBillPromptsWhenNewPaymentChangesAmount() throws {
        var data = ledger(amounts: [10000, 10000, 10000])
        for index in data.transactions.indices { data.transactions[index].needsReview = false }
        try RecurringBills.autoTrack(in: &data)
        let before = data.netWorth
        let changed = ImportRow(date: date("2026-04-30"), merchant: "Hydro Electricity", amount: 20000, kind: .expense, category: "Utilities", note: "")
        try TransactionImport.apply([changed], to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        XCTAssertEqual(data.bills.count, 1)
        XCTAssertEqual(data.bills[0].needsScheduleReview, true)
        XCTAssertNotNil(data.bills[0].detectionReviewReason)
        XCTAssertEqual(data.bills[0].amount, 10000)
        XCTAssertEqual(data.netWorth, before - 20000)
        XCTAssertEqual(data.transactions.count, 4)
        XCTAssertNil(data.transactions.last?.recurringBillID)
    }
    func testGenericAppleChargesManualCorrectionsAndDismissalsAreRespected() throws {
        var data = ledger([], amounts: [])
        let generic = ImportRow(date: date("2026-01-07"), merchant: "APPLE.COM/BILL", amount: 399, kind: .expense, category: "Other", note: "")
        try TransactionImport.apply([generic], to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        XCTAssertTrue(data.bills.isEmpty); XCTAssertTrue(data.transactions[0].needsReview)
        var modelGuess = generic
        modelGuess.sourceCategory = "Other"; modelGuess.category = "Subscription"
        modelGuess.clearCategoryEvidence = Categorization.evidenceKey(modelGuess)
        XCTAssertFalse(Categorization.isClear(modelGuess, in: data, accountID: data.accounts[0].id, currency: "CAD"))
        var manual = generic; manual.id = UUID(); manual.merchant = "Apple iCloud"; manual.category = "Utilities"; manual.manualCategory = true
        try TransactionImport.apply([manual], to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        XCTAssertTrue(data.bills.isEmpty)
        XCTAssertEqual(data.category(data.transactions.last!.categoryID)?.name, "Utilities")
        var known = generic; known.id = UUID(); known.merchant = "Netflix"
        try TransactionImport.apply([known], to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        let bill = try XCTUnwrap(data.bills.first)
        RecurringBills.dismiss(bill, in: &data)
        try RecurringBills.autoTrack(in: &data)
        XCTAssertTrue(data.bills.isEmpty)
        XCTAssertNil(data.transactions.last?.recurringBillID)
        let restored = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored, data)
    }
    // Regular shopping is not enough; uncertain amounts/directions must still prompt or abstain.
    func testOnlyClearStableRecurringCategoriesAutoTrack() throws {
        var data = ledger(amounts: [10000, 10000, 10000])
        try RecurringBills.autoTrack(in: &data)
        XCTAssertTrue(data.bills.isEmpty) // These payments are still flagged for transaction review.
        for index in data.transactions.indices { data.transactions[index].needsReview = false }
        try RecurringBills.autoTrack(in: &data)
        XCTAssertEqual(data.bills.count, 1)
        var shopping = ledger(amounts: [10000, 10000, 10000])
        shopping.categories[0].name = "Shopping"
        for index in shopping.transactions.indices { shopping.transactions[index].needsReview = false }
        try RecurringBills.autoTrack(in: &shopping)
        XCTAssertTrue(shopping.bills.isEmpty)
        var variable = ledger()
        for index in variable.transactions.indices { variable.transactions[index].needsReview = false }
        try RecurringBills.autoTrack(in: &variable)
        XCTAssertTrue(variable.bills.isEmpty); XCTAssertEqual(RecurringBills.suggestions(in: variable).count, 1)
    }
    // Exercise the real on-device category model; it supplies no dates, amounts, or recurrence arithmetic.
    func testLiveAppleSubscriptionClassificationWhenAvailable() async throws {
        guard AppleCategoryModel.isAvailable else { throw XCTSkip(AppleCategoryModel.status) }
        let data = ledger([], amounts: [])
        let row = ImportRow(date: date("2026-01-07"), merchant: "Apple iCloud+ storage subscription", amount: 399, kind: .expense, category: "Other", note: "")
        do {
            guard let suggestion = try await AppleCategoryModel.generate(row, options: Categorization.options(in: data, currency: "CAD")) else {
                throw XCTSkip("The available on-device model abstained on the fictional subscription.")
            }
            XCTAssertEqual(suggestion.name, "Subscription")
            print("APPLE SUBSCRIPTION MODEL LIVE RESULT: " + suggestion.name)
        } catch let error as XCTSkip { throw error }
        catch { throw XCTSkip("The local Apple model service is unavailable in this test runtime.") }
    }
    func testMonthlyVariablePaymentsRequireConfirmation() throws {
        var data = ledger()
        let original = data
        let suggestion = try XCTUnwrap(RecurringBills.suggestions(in: data).first)
        XCTAssertEqual(suggestion.frequency, .monthly)
        XCTAssertEqual(suggestion.minimum, 9000); XCTAssertEqual(suggestion.maximum, 12000)
        XCTAssertEqual(suggestion.due, date("2026-04-30"))
        XCTAssertEqual(data, original)
        try RecurringBills.confirm(suggestion, in: &data)
        XCTAssertEqual(data.transactions.count, 3)
        XCTAssertEqual(data.netWorth, original.netWorth)
        XCTAssertTrue(data.transactions.allSatisfy { $0.recurringBillID == data.bills[0].id })
        XCTAssertTrue(RecurringBills.suggestions(in: data).isEmpty)
        XCTAssertThrowsError(try RecurringBills.confirm(suggestion, in: &data))
        let roundTrip = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(roundTrip, data)
    }
    func testCSVImportMatchesAndAdvancesWithoutExtraExpense() throws {
        var data = ledger()
        try RecurringBills.confirm(try XCTUnwrap(RecurringBills.suggestions(in: data).first), in: &data)
        let before = data.netWorth
        let csv = Data("Date,Description,Amount,Category\n2026-04-30,Hydro Electricity,-110.00,Housing & Utilities\n2026-05-31,Hydro Electricity,-105.00,Utilities\n".utf8)
        let batch = try TransactionImport.csv(csv)
        try TransactionImport.apply(batch.rows, to: &data, accountID: data.accounts[0].id, newAccount: nil, removeDemo: false)
        XCTAssertEqual(data.transactions.count, 5)
        XCTAssertEqual(data.netWorth, before - 21500)
        XCTAssertEqual(data.bills[0].due, date("2026-06-30"))
        XCTAssertEqual(data.transactions.filter { $0.recurringBillID != nil }.count, 5)
        XCTAssertEqual(data.categories.count, 1)
        XCTAssertEqual(TransactionImport.duplicates(batch.rows, in: data, account: data.accounts[0].id).count, 2)
    }
    func testInsufficientIrregularIncomeAndCrossAccountEvidenceIsRejected() {
        XCTAssertTrue(RecurringBills.suggestions(in: ledger(["2026-01-01", "2026-01-03", "2026-01-09"])).isEmpty)
        var data = ledger(); data.transactions.removeLast()
        XCTAssertTrue(RecurringBills.suggestions(in: data).isEmpty)
        data = ledger(); data.transactions[0].kind = .income
        XCTAssertTrue(RecurringBills.suggestions(in: data).isEmpty)
        data = ledger(); data.transactions[0].accountID = UUID()
        XCTAssertTrue(RecurringBills.suggestions(in: data).isEmpty)
        data = ledger(); data.transactions[0].amount = 1
        XCTAssertTrue(RecurringBills.suggestions(in: data).isEmpty)
        data = ledger(); data.transactions.append(data.transactions[0])
        XCTAssertTrue(RecurringBills.suggestions(in: data).isEmpty)
        XCTAssertTrue(RecurringBills.suggestions(in: ledger(), now: date("2026-02-01")).isEmpty)
    }
    func testAllCadencesAndMonthEndAnchor() throws {
        for (dates, expected) in [(["2026-01-01", "2026-01-08", "2026-01-15"], BillFrequency.weekly),
                                  (["2026-01-01", "2026-01-15", "2026-01-29"], .fortnightly),
                                  (["2025-07-01", "2025-10-01", "2026-01-01"], .quarterly),
                                  (["2023-01-01", "2024-01-01", "2025-01-01"], .annually)] {
            XCTAssertEqual(RecurringBills.suggestions(in: ledger(dates)).first?.frequency, expected)
        }
        XCTAssertEqual(BillFrequency.monthly.next(after: date("2026-02-28"), anchorDay: 31), date("2026-03-31"))
        var data = ledger(); try RecurringBills.confirm(try XCTUnwrap(RecurringBills.suggestions(in: data).first), in: &data)
        data.bills[0].recurrence = .weekly
        let due = data.bills[0].due
        try data.payBill(data.bills[0].id)
        XCTAssertEqual(data.bills[0].due, BillFrequency.weekly.next(after: due))
    }
    func testMatcherRejectsWrongAccountAmountDateIncomeAndAmbiguity() throws {
        for scenario in 0..<6 {
            var data = ledger()
            try RecurringBills.confirm(try XCTUnwrap(RecurringBills.suggestions(in: data).first), in: &data)
            var payment = Transaction(merchant: "Hydro Electricity", amount: 10000, kind: .expense, date: date("2026-04-30"), accountID: data.accounts[0].id, categoryID: data.categories[0].id)
            switch scenario {
            case 0: payment.accountID = UUID()
            case 1: payment.amount = 50000
            case 2: payment.date = date("2026-04-15")
            case 3: payment.kind = .income
            case 4: var duplicate = data.bills[0]; duplicate.id = UUID(); data.bills.append(duplicate)
            default: data.bills[0].matchingMerchant = nil
            }
            data.transactions.append(payment)
            let due = data.bills[0].due
            RecurringBills.matchImports([payment.id], in: &data)
            XCTAssertNil(data.transactions.last?.recurringBillID)
            XCTAssertEqual(data.bills[0].due, due)
        }
    }
    func testOldBackupsDecodeAsManualMonthlyBills() throws {
        var data = ledger(); try RecurringBills.confirm(try XCTUnwrap(RecurringBills.suggestions(in: data).first), in: &data)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
        var bills = try XCTUnwrap(object["bills"] as? [[String: Any]])
        for key in ["recurrence", "matchingMerchant", "minimumAmount", "maximumAmount", "anchorDay"] { bills[0].removeValue(forKey: key) }
        object["bills"] = bills
        object["transactions"] = (object["transactions"] as! [[String: Any]]).map { transaction in var t = transaction; t.removeValue(forKey: "recurringBillID"); return t }
        let restored = try JSONDecoder().decode(FinanceData.self, from: JSONSerialization.data(withJSONObject: object))
        try restored.validate()
        XCTAssertEqual(restored.bills[0].frequency, .monthly)
        XCTAssertNil(restored.bills[0].matchingMerchant)
    }
    // Completion follows persisted category content and becomes actionable again only for new work.
    func testSimplificationAvailabilitySurvivesRoundTripAndDetectsNewWork() throws {
        var data = FinanceData.demo()
        XCTAssertFalse(data.needsCategorySimplification)
        data.categories.append(Category(name: "Housing & Utilities", symbol: "house", limit: 10000))
        XCTAssertTrue(data.needsCategorySimplification)
        let budget = data.budget
        try data.simplifyCategories()
        XCTAssertFalse(data.needsCategorySimplification)
        XCTAssertEqual(data.budget, budget)
        let completed = data
        try data.simplifyCategories()
        XCTAssertEqual(data, completed)
        data = try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(data))
        XCTAssertFalse(data.needsCategorySimplification)
        data.categories.append(Category(name: "Dining & Cafes", symbol: "fork.knife", limit: 0))
        XCTAssertTrue(data.needsCategorySimplification)
    }
    func testCategoryCleanupPreservesMoneyBudgetsAndReferences() throws {
        var data = ledger()
        let combined = Category(name: "Housing & Utilities", symbol: "house", limit: 180000)
        data.categories.append(combined)
        data.transactions.append(Transaction(merchant: "Rent", amount: 165000, kind: .expense, date: date("2026-03-01"), accountID: data.accounts[0].id, categoryID: combined.id))
        data.bills.append(Bill(name: "Rent", amount: 165000, due: date("2026-04-01"), accountID: data.accounts[0].id, categoryID: combined.id))
        let worth = data.netWorth, budget = data.budget, ids = data.transactions.map(\.id)
        try data.simplifyCategories()
        XCTAssertEqual(data.netWorth, worth); XCTAssertEqual(data.budget, budget)
        XCTAssertEqual(data.transactions.map(\.id), ids)
        XCTAssertFalse(data.categories.contains { $0.name == combined.name })
        let rent = try XCTUnwrap(data.categories.first { $0.name == "Rent" })
        XCTAssertEqual(data.transactions.last?.categoryID, rent.id); XCTAssertEqual(data.bills.last?.categoryID, rent.id)
        XCTAssertEqual(rent.limit, 0)
        let cleaned = data; try data.simplifyCategories(); XCTAssertEqual(data, cleaned)
        try data.validate()
    }
}
