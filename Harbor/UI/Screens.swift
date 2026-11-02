import SwiftUI

// Category labels use SymbolGlyph so custom emojis render consistently with built-in icons.
import Charts

struct HomeScreen: View {
    @EnvironmentObject var store: HarborStore
    @Binding var tab: Int
    @State private var edit: Transaction?
    @State private var selectedBudgetCategory: Category?
    @ScaledMetric(relativeTo: .body) private var tileSide: CGFloat = 170
    private var monthlyCategories: [Category] { store.data.usedCategories(in: store.month, currency: store.data.reportingCurrency, kind: .expense).map(store.budgetCategory) }
    var body: some View {
        Screen {
            if store.data.isDemo { Label("Demo data · Start fresh in Settings", systemImage: "info.circle").font(.caption).foregroundStyle(HarborStyle.blue) }
            // Keep the greeting and month together so the balance starts higher on Home.
            ViewThatFits(in: .horizontal) {
                HStack { Text("Hello, \(store.data.name)").font(.title2.bold()).lineLimit(1); Spacer(); CompactMonthPicker() }
                VStack(alignment: .leading) { Text("Hello, \(store.data.name)").font(.title2.bold()); CompactMonthPicker() }
            }
            // Put the daily action above balances so it is reachable without scrolling Home.
            DailyCheckInCard(compact: true)
            HarborCard(dark: true) {
                Text("TOTAL NET WORTH").font(.caption.bold()).foregroundStyle(HarborStyle.heroAccent)
                MoneyLabel(cents: store.data.netWorth, size: 36)
                Text("\(store.data.reportingCurrency) · Native balances; no currency conversion").font(.caption).opacity(0.7)
                ForEach(store.data.currencies.filter { $0 != store.data.reportingCurrency }, id: \.self) { currency in
                    HStack { Text(currency); Spacer(); Text(store.format(store.data.netWorth(in: currency), currency: currency)) }.font(.subheadline)
                }
                HStack {
                    Stat(title: "Income", cents: store.data.total(.income, in: store.month))
                    Stat(title: "Spent", cents: store.data.total(.expense, in: store.month))
                    // An unset limit cannot supply a meaningful remaining-budget amount.
                    if store.monthlyBudget > 0 { Stat(title: "Budget left", cents: store.monthlyBudget - store.data.total(.expense, in: store.month)) }
                }
            }
            HarborCard {
                Label("Your financial briefing", systemImage: "sparkles").font(.headline).foregroundStyle(HarborStyle.blue)
                Text(briefing).font(.subheadline).accessibilityIdentifier("home.briefing")
            }
            HomeWeeklySpending()
            NavigationLink("Top spending categories") { AnalyticsScreen() }.accessibilityIdentifier("home.topCategories")
            // Detected reminders may have variable amounts as well as fixed payments.
            HStack { SectionTitle(title: "Upcoming Bills"); Spacer(); NavigationLink("Manage") { BillsScreen() }.font(.subheadline) }
            if store.data.bills.isEmpty { EmptyCard(title: "No bills yet", detail: "Add recurring bills with Manage.") }
            // Horizontal square tiles keep every bill reachable without stretching the page.
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 12) {
                    ForEach(store.data.bills.sorted { $0.due < $1.due }) { bill in
                        NavigationLink { BillsScreen() } label: {
                            HomeSquareCard {
                                // Share the icon row with the receipt so the square stays compact.
                                HStack {
                                    IconTile(symbol: "calendar")
                                    Spacer()
                                    if bill.isPaymentComplete() { Label("Paid", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(HarborStyle.teal) }
                                }
                                Text(bill.name).font(.subheadline.bold()).lineLimit(2)
                                Text("Next due " + bill.due.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                MoneyLabel(cents: bill.amount, size: 20, currency: store.data.currency(bill.accountID))
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(.bottom, 5)
            }.accessibilityIdentifier("home.bills")
            HStack { SectionTitle(title: "Budget Health"); Spacer(); Button("View all") { tab = 2 }.font(.subheadline) }
            // Empty saved categories do not appear until spending uses them in the selected month.
            if monthlyCategories.isEmpty { EmptyCard(title: "No spending categories this month", detail: "Categories appear as you record or import transactions.") } else {
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHGrid(rows: [GridItem(.fixed(tileSide)), GridItem(.fixed(tileSide))], spacing: 12) {
                    ForEach(monthlyCategories) { category in
                        Button { selectedBudgetCategory = category } label: {
                            HomeSquareCard {
                                // Each pig fills with selected-month spending; the text retains uncapped usage.
                                HStack {
                                    PiggyBankGauge(progress: category.limit > 0 ? budgetRatio(category) : nil).frame(width: 82, height: 58)
                                    Spacer(minLength: 0)
                                    Text(budgetPercent(category)).font(.caption.bold()).foregroundStyle(HarborStyle.navy)
                                }
                                Label { Text(category.name) } icon: { SymbolGlyph(symbol: category.symbol) }.font(.subheadline.bold()).lineLimit(2)
                                Spacer(minLength: 0)
                                MoneyLabel(cents: store.data.total(.expense, in: store.month, category: category.id), size: 20)
                                Text(category.limit > 0 ? "/ \(store.format(category.limit))" : "Monthly limit not set").font(.caption).foregroundStyle(.secondary)
                            }
                        // Forward card presses to the pig while keeping the whole tile navigable.
                        }.buttonStyle(PiggyBankCardStyle()).accessibilityIdentifier("home.budget.\(category.name)")
                    }
                }.padding(.bottom, 5)
            }.frame(height: tileSide * 2 + 17).accessibilityIdentifier("home.budgets")
            }
            HStack { SectionTitle(title: "Recent Activity"); Spacer(); Button("See all") { tab = 1 }.font(.subheadline) }
            HarborCard {
                if store.data.transactions.isEmpty { Text("Add your first transaction with +.").foregroundStyle(.secondary) }
                ForEach(store.data.transactions.sorted { $0.date > $1.date }.prefix(4)) { entry in Button { edit = entry } label: { LedgerRow(transaction: entry) }.buttonStyle(.plain) }
            }
        }.sheet(item: $edit) { TransactionEditor(existing: $0) }
        // Home cards open the same month-scoped transaction detail as the Budget screen.
        .sheet(item: $selectedBudgetCategory) { BudgetCategoryTransactionsScreen(categoryID: $0.id, month: store.month) }
    }
    private func budgetRatio(_ category: Category) -> Double {
        guard category.limit > 0 else { return 0 }
        return Double(store.data.total(.expense, in: store.month, category: category.id)) / Double(category.limit)
    }
    private func budgetPercent(_ category: Category) -> String {
        guard category.limit > 0 else { return "Unset" }
        return "\(Int(Double(store.data.total(.expense, in: store.month, category: category.id)) / Double(category.limit) * 100))%"
    }
    private var briefing: String {
        let remaining = store.monthlyBudget - store.data.total(.expense, in: store.month)
        // The monthly briefing uses Activity's month scope, including every account and currency.
        let reviews = store.data.entries(in: store.month).filter(\.needsReview).count
        let reviewSummary = reviews == 0 ? "All reviewed this month." : "\(reviews) transaction\(reviews == 1 ? " needs" : "s need") review this month."
        // Spending still updates from transactions when no budget has been configured.
        if store.monthlyBudget == 0 {
            return "Spent \(store.format(store.data.total(.expense, in: store.month))) this month. No monthly budget limit set. \(reviewSummary)"
        }
        return "\(store.format(abs(remaining))) \(remaining >= 0 ? "left in your budget" : "over budget") this month. \(reviewSummary)"
    }
}

struct ActivityScreen: View {
    @EnvironmentObject var store: HarborStore
    @FocusState private var searchFocused: Bool
    @State private var search = ""
    @State private var reviewOnly = false
    @State private var account: UUID?
    @State private var category: UUID?
    @State private var edit: Transaction?
    @State private var reviewAll = false
    private var entries: [Transaction] {
        store.data.entries(in: store.month).filter { entry in
            (!reviewOnly || entry.needsReview) && (account == nil || account == entry.accountID) && (category == nil || category == entry.categoryID) && (search.isEmpty || "\(entry.merchant) \(entry.note) \(store.data.category(entry.categoryID)?.name ?? "")".localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        Screen {
            // Match Home's compact month placement; larger text can wrap the header without clipping.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { activitySearch.frame(minWidth: 130); CompactMonthPicker().fixedSize() }
                VStack(alignment: .leading, spacing: 12) { activitySearch; HStack { Spacer(); CompactMonthPicker() } }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button { reviewOnly.toggle() } label: { Label("Needs Review", systemImage: reviewOnly ? "flag.fill" : "flag") }.buttonStyle(.bordered).tint(reviewOnly ? HarborStyle.blue : .gray)
                    Picker("Account", selection: $account) { Text("All accounts").tag(nil as UUID?); ForEach(store.data.accounts) { Text("\($0.name) · \($0.currency)").tag(Optional($0.id)) } }.pickerStyle(.menu)
                    // Offer only categories used in this month's activity, across its displayed currencies.
                    Picker("Category", selection: $category) { Text("All categories").tag(nil as UUID?); ForEach(store.data.usedCategories(in: store.month)) { Text($0.name).tag(Optional($0.id)) } }.pickerStyle(.menu)
                }
            }
            HarborCard {
                Text("\(entries.count) transactions").font(.headline)
                // Totals remain separate even when Activity displays several currencies together.
                ForEach(Array(Set(entries.map { store.data.currency($0.accountID) })).sorted(), id: \.self) { currency in
                    Text(currency).font(.caption)
                    HStack { Stat(currency: currency, title: "Spent", cents: entries.filter { !$0.isTransfer && $0.kind == .expense && store.data.currency($0.accountID) == currency }.reduce(0) { $0 + $1.amount }); Stat(currency: currency, title: "Income", cents: entries.filter { !$0.isTransfer && $0.kind == .income && store.data.currency($0.accountID) == currency }.reduce(0) { $0 + $1.amount }) }
                }
                if entries.contains(where: \.needsReview) { Button("Mark visible transactions reviewed") { reviewAll = true }.font(.subheadline) }
            }
            if entries.isEmpty { EmptyCard(title: "No transactions found", detail: "Try another month or filter, or add a transaction.") }
            ForEach(groupedDates, id: \.self) { date in
                Text(date.formatted(date: .complete, time: .omitted)).font(.caption.bold()).foregroundStyle(.secondary)
                HarborCard { ForEach(entries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }) { entry in Button { edit = entry } label: { LedgerRow(transaction: entry) }.buttonStyle(.plain) } }
            }
            Text("Manual records · Saved on this device").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
        .sheet(item: $edit) { TransactionEditor(existing: $0) }
        .onChange(of: store.month) { _, _ in category = nil }
        .confirmationDialog("Mark all visible transactions reviewed?", isPresented: $reviewAll, titleVisibility: .visible) {
            Button("Mark reviewed") {
                let ids = Set(entries.map(\.id))
                // Explicit confirmation makes these authoritative human-reviewed examples.
                store.update { data in for i in data.transactions.indices where ids.contains(data.transactions[i].id) { data.transactions[i].needsReview = false; data.transactions[i].automaticallyReviewed = nil } }
            }
        }
    }
    // System foregrounds, a distinct surface and a visible border keep search readable in both modes.
    private var activitySearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.primary).accessibilityHidden(true)
            TextField("Search activity", text: $search, prompt: Text("Search activity").foregroundColor(HarborStyle.searchPrompt))
                .font(.subheadline).foregroundStyle(.primary).tint(HarborStyle.blue)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).focused($searchFocused).onSubmit { searchFocused = false }.accessibilityLabel("Search transactions").accessibilityIdentifier("activity.search")
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.primary).frame(minWidth: 28, minHeight: 36) }
                    .accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, 12).frame(minHeight: 48)
            .background(HarborStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.4), lineWidth: 1) }
    }
    private var groupedDates: [Date] { Array(Set(entries.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >) }
}

// Categories explores recorded activity; limits and piggy-bank health remain in Budget.
struct CategoriesScreen: View {
    @EnvironmentObject private var store: HarborStore
    @State private var search = ""
    @State private var showSaved = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selected: Category?
    @FocusState private var searching: Bool

    var body: some View {
        // Group once per render, using the same month/currency/transfer rules as the ledger reports.
        let entries = store.data.reportingEntries(in: store.month)
        let grouped = Dictionary(grouping: entries, by: \.categoryID)
        let saved = store.data.reportingCategories
        let used = saved.filter { grouped[$0.id] != nil }
        let categories = (showSaved ? saved : used).filter {
            search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.name.localizedStandardContains(search.trimmingCharacters(in: .whitespacesAndNewlines))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Screen {
            MonthPicker()
            // Keep browsing compact; creation and organization remain in Settings.
            Picker("Categories to show", selection: $showSaved) {
                Text("This month").tag(false)
                Text("All saved").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("categories.scope")
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                // Match Activity's explicit prompt color so search stays readable in dark appearance.
                TextField("Find a category", text: $search, prompt: Text("Find a category").foregroundColor(HarborStyle.searchPrompt))
                    .focused($searching).foregroundStyle(.primary).tint(HarborStyle.blue)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .onSubmit { searching = false }.accessibilityIdentifier("categories.search")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel("Clear category search")
                }
            }.padding(.horizontal, 14).frame(minHeight: 48)
                .background(HarborStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            if categories.isEmpty {
                EmptyCard(title: search.isEmpty ? "A fresh page" : "No matching categories", detail: search.isEmpty ? "Categories appear as you add transactions. Choose All saved to explore your collection, or create one in Settings → Categories → Manage categories." : "Try another name, or choose All saved.")
            }
            // Accessibility sizes get the full width so names and currency amounts can grow.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                ForEach(categories) { category in
                    let transactions = grouped[category.id, default: []]
                    let spent = transactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
                    let income = transactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
                    Button { searching = false; selected = category } label: {
                        CategoryGridTile(category: category, amount: spent == 0 && income > 0 ? income : spent,
                                         received: spent == 0 && income > 0, count: transactions.count, color: categoryColor(category))
                    }.buttonStyle(.plain).accessibilityIdentifier("categories.view." + category.name)
                }
            }.accessibilityIdentifier("categories.grid")
            if !categories.isEmpty {
                Text("Make it yours: add an emoji or change a name inside any category.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $selected) { BudgetCategoryTransactionsScreen(categoryID: $0.id, month: store.month, categoryContext: true) }
        .onChange(of: store.month) { _, _ in showSaved = false; search = ""; searching = false }
        .onChange(of: store.data.reportingCurrency) { _, _ in search = "" }
    }

    private func categoryColor(_ category: Category) -> Color {
        let colors: [Color] = [HarborStyle.blue, HarborStyle.teal, .purple, .pink, .orange]
        return colors[category.name.utf8.reduce(0) { $0 + Int($1) } % colors.count]
    }
}

// A tile uses Harbor's existing card palette while allowing content to wrap at narrow widths.
private struct CategoryGridTile: View {
    @EnvironmentObject private var store: HarborStore
    let category: Category
    let amount: Int
    let received: Bool
    let count: Int
    let color: Color
    @ScaledMetric(relativeTo: .title) private var amountSize = 23.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Decorative glyphs stay within their tile while the readable text scales independently.
            SymbolGlyph(symbol: category.symbol).font(.system(size: 24))
                .foregroundStyle(color).frame(width: 48, height: 48)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            Text(category.name).font(.headline).fixedSize(horizontal: false, vertical: true)
            // Unlike the shared single-line MoneyLabel, grid amounts can wrap without clipping.
            Text(store.format(amount, currency: category.currency))
                .font(.system(size: amountSize, weight: .bold, design: .rounded)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if received { Text("received").font(.caption).foregroundStyle(.secondary) }
            Text("\(count) \(count == 1 ? "transaction" : "transactions")")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
        .background(HarborStyle.surface, in: RoundedRectangle(cornerRadius: 26))
        .foregroundStyle(HarborStyle.navy)
        // Speak a complete tile once, including currency and whether the amount was received.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.name), \(store.format(amount, currency: category.currency)) \(category.currency) \(received ? "received" : "spent"), \(count) \(count == 1 ? "transaction" : "transactions")")
    }
}

struct BudgetCard: View {
    @EnvironmentObject var store: HarborStore
    let category: Category
    let action: () -> Void
    @ScaledMetric(relativeTo: .title) private var amountSize = 23.0
    private var spent: Int { store.data.total(.expense, in: store.month, category: category.id) }
    private var ratio: Double { Double(spent) / Double(max(1, category.limit)) }
    var body: some View {
        Button(action: action) {
            // Stack planning details vertically so two cards fit without squeezing names or amounts.
            VStack(alignment: .leading, spacing: 10) {
                PiggyBankGauge(progress: category.limit > 0 ? ratio : nil).frame(width: 112, height: 82)
                Label { Text(category.name).fixedSize(horizontal: false, vertical: true) } icon: {
                    SymbolGlyph(symbol: category.symbol).font(.system(size: 18))
                }.font(.headline)
                Text(category.limit == 0 ? "No budget" : ratio > 1 ? "Over budget" : ratio == 1 ? "Budget reached" : ratio >= 0.85 ? "Near limit" : "On track")
                    .font(.caption).foregroundStyle(category.limit > 0 && ratio > 1 ? .red : HarborStyle.navy)
                // Grid amounts wrap rather than clipping the shared single-line money label.
                Text(store.format(spent, currency: category.currency))
                    .font(.system(size: amountSize, weight: .bold, design: .rounded)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(store.format(spent, currency: category.currency) + " " + category.currency + " spent")
                if category.limit > 0 {
                    Text("of \(store.format(category.limit, currency: category.currency)) limit").font(.caption)
                    Text("\(Int(ratio * 100))% used").font(.caption)
                    Text("\(store.format(abs(category.limit - spent), currency: category.currency)) \(spent > category.limit ? "over" : "left")").font(.caption)
                } else {
                    // Zero remains an unset limit; it never becomes a percentage denominator.
                    Text("Spent this month · No monthly limit set").font(.caption)
                }
                // The full estimate explanation remains in the existing transaction detail sheet.
                Text(category.usesAutomaticBudget ? "Automatic budget" : "Manual budget")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
            .background(HarborStyle.surface, in: RoundedRectangle(cornerRadius: 26))
            .foregroundStyle(HarborStyle.navy)
            .accessibilityElement(children: .combine)
            .accessibilityHint("View transactions and budget")
        }.buttonStyle(PiggyBankCardStyle())
    }
}

struct BudgetScreen: View {
    @EnvironmentObject var store: HarborStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var filter = "All"
    @State private var editing: Category?
    @State private var creating = false
    @State private var spendingTab = BudgetSpendingTab.current
    @State private var explainingForecast = false
    private let filters = ["All", "On track", "Near limit", "Exceeded"]
    private var categories: [Category] {
        // Budget cards follow recorded spending for this month rather than the entire saved catalog.
        store.data.usedCategories(in: store.month, currency: store.data.reportingCurrency, kind: .expense).map(store.budgetCategory).filter { c in
            let ratio = Double(store.data.total(.expense, in: store.month, category: c.id)) / Double(max(c.limit, 1))
            return filter == "All" || c.limit > 0 && ((filter == "On track" && ratio < 0.85) || (filter == "Near limit" && ratio >= 0.85 && ratio < 1) || (filter == "Exceeded" && ratio >= 1))
        }
    }
    var body: some View {
        Screen {
            MonthPicker()
            // Analysis is discoverable from Budget, alongside the spending users are exploring.
            NavigationLink { AnalyticsScreen() } label: {
                HarborCard { HStack { Label("Spending Analytics", systemImage: "chart.xyaxis.line"); Spacer(); Image(systemName: "chevron.right") } }
            }.buttonStyle(.plain).accessibilityIdentifier("budget.analytics")
            // Keep recorded budgets and predictions in distinct, accessible views of the same month.
            Picker("Budget spending view", selection: $spendingTab) {
                ForEach(BudgetSpendingTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
            }.pickerStyle(.segmented).accessibilityIdentifier("budget.spendingTabs")
            if spendingTab == .forecast {
                HStack {
                    Text("Forecasted Spending").font(.headline)
                    Spacer()
                    Button { explainingForecast = true } label: { Image(systemName: "info.circle").font(.title3).frame(width: 44, height: 44) }
                        .accessibilityLabel("About Forecasted Spending").accessibilityIdentifier("budget.forecastInfo")
                }
                let forecast = SpendingForecast.calculate(data: store.data, month: store.month)
                ForecastCard(forecast: forecast)
                if let estimate = forecast.estimate, !forecast.isHistorical, store.monthlyBudget > 0 {
                    HarborCard {
                        Text(estimate <= store.monthlyBudget ? "Projected budget remaining" : "Projected over budget").font(.headline)
                        MoneyLabel(cents: abs(store.monthlyBudget - estimate))
                        Text("Compared with your \(store.format(store.monthlyBudget)) monthly allocation.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HarborCard {
                    Text("Forecast trajectory").font(.title3.bold())
                    SpendingChart(mode: .forecast).frame(height: 240)
                    Text("Blue: recorded spending · Teal dashed: estimated spending").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HarborCard(dark: true) {
                    Text("MASTER ENVELOPE · \(store.data.reportingCurrency)").font(.caption.bold())
                    MoneyLabel(cents: store.data.total(.expense, in: store.month), size: 36)
                    if store.monthlyBudget > 0 {
                        Text("of \(store.format(store.monthlyBudget)) monthly allocation").font(.subheadline)
                        ProgressView(value: min(Double(store.data.total(.expense, in: store.month)) / Double(store.monthlyBudget), 1)).tint(HarborStyle.heroAccent)
                        Stat(title: "Safe to spend", cents: store.monthlyBudget - store.data.total(.expense, in: store.month))
                    } else { Text("Spent this month · Monthly limit not set").font(.caption) }
                }
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(filters, id: \.self) { value in FilterChip(title: value, selected: filter == value) { filter = value } } } }
                // Match Categories' grid, giving accessibility text sizes a full-width card.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach(categories) { c in BudgetCard(category: c) { editing = c }.accessibilityIdentifier("budget.category." + c.name) }
                }.accessibilityIdentifier("budget.grid")
                if categories.isEmpty { EmptyCard(title: "No spending categories here", detail: "Categories appear from this month's transactions. Try another month or filter.") }
                NavigationLink("Manage saved categories") { CategoryManagementScreen() }
                Button { creating = true } label: { Label("Create Custom Category", systemImage: "plus.circle").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent)
                Text("Only categories used this month are shown. Automatic limits average recorded spending in the previous three completed calendar months, skipping months with no recorded activity in that currency. Current-month spending never raises its own limit. Incomplete records can understate estimates. Manual limits repeat each month; hidden categories remain in the total allocation. Manage saved categories to change limits.").font(.caption).foregroundStyle(.secondary)
            }
        }.sheet(isPresented: $explainingForecast) { ForecastExplanation() }
        // Open the selected month's ledger first, with budget editing available inside the detail sheet.
        .sheet(item: $editing) { BudgetCategoryTransactionsScreen(categoryID: $0.id, month: store.month) }
        .sheet(isPresented: $creating) { CategoryEditor() }
    }
}

struct BudgetCategoryTransactionsScreen: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    let categoryID: UUID
    let month: Date
    // Reuse the ledger drill-down while making category editing explicit from the Categories tab.
    var categoryContext = false
    @State private var editingBudget = false
    @State private var editingTransaction: Transaction?
    // A drill-down keeps the same historical month even if another screen changes its selection.
    private var budgetPlan: AutomaticBudgets { AutomaticBudgets.calculate(data: store.data, month: month) }
    private var category: Category? { store.data.category(categoryID).map { budgetPlan.resolved($0) } }
    private var entries: [Transaction] {
        // Match this category and month without mixing currencies or linked transfer movements into spending.
        store.data.entries(in: month).filter {
            $0.categoryID == categoryID && !$0.isTransfer && store.data.currency($0.accountID) == category?.currency
        }
    }
    var body: some View {
        NavigationStack {
            Screen {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline).accessibilityIdentifier("categoryTransactions.month")
                if let category {
                    HarborCard {
                        Label { Text(category.name) } icon: { SymbolGlyph(symbol: category.symbol) }.font(.title2.bold())
                        HStack {
                            Stat(currency: category.currency, title: "Spent", cents: entries.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount })
                            if category.limit > 0 { Stat(currency: category.currency, title: "Monthly limit", cents: category.limit) }
                        }
                        // Imported categories have real spending before a monthly limit is chosen.
                        if category.limit == 0 { Text("Monthly limit not set").font(.caption).foregroundStyle(.secondary) }
                        if !categoryContext { Text(budgetPlan.note(for: category)).font(.caption).foregroundStyle(.secondary) }
                        if entries.contains(where: { $0.kind == .income }) {
                            Stat(currency: category.currency, title: "Income", cents: entries.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount })
                        }
                        Button(categoryContext ? "Edit category" : "Edit budget") { editingBudget = true }
                            .accessibilityIdentifier(categoryContext ? "categoryTransactions.editCategory" : "categoryTransactions.editBudget")
                    }
                    Text("\(entries.count) transactions").font(.headline).accessibilityIdentifier("categoryTransactions.count")
                    if entries.isEmpty { EmptyCard(title: "No transactions in this category", detail: "There are no transactions for this category in the selected month.") }
                    // Native ledger rows keep account, direction, date, amount, and review status consistent with Activity.
                    ForEach(entries) { entry in
                        Button { editingTransaction = entry } label: {
                            HarborCard {
                                Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                LedgerRow(transaction: entry)
                            }
                        }
                            .buttonStyle(.plain).accessibilityIdentifier("categoryTransactions.entry." + entry.merchant)
                    }
                } else { EmptyCard(title: "Category no longer available", detail: "Close this view to choose another category.") }
            }.navigationTitle("Category transactions").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $editingBudget) { if let category { CategoryEditor(existing: category, categoryFirst: categoryContext) } }
                .sheet(item: $editingTransaction) { TransactionEditor(existing: $0) }
        }
    }
}

struct GoalsScreen: View {
    @EnvironmentObject var store: HarborStore
    @State private var filter = "All Goals"
    @State private var editing: Goal?
    @State private var creating = false
    private var goals: [Goal] { store.data.goals.filter { filter == "All Goals" || (filter == "In Progress" && $0.saved < $0.target) || (filter == "High Priority" && $0.highPriority) || (filter == "Completed" && $0.saved >= $0.target) } }
    var body: some View {
        Screen {
            HarborCard(dark: true) {
                Text("TOTAL SAVED ACROSS GOALS").font(.caption.bold())
                MoneyLabel(cents: store.data.reportingGoals.reduce(0) { $0 + $1.saved }, size: 36)
                Text("of \(store.format(store.data.reportingGoals.reduce(0) { $0 + $1.target })) target · \(store.data.reportingCurrency)").font(.subheadline)
                ProgressView(value: Double(store.data.reportingGoals.reduce(0) { $0 + $1.saved }), total: Double(max(1, store.data.reportingGoals.reduce(0) { $0 + $1.target }))).tint(HarborStyle.heroAccent)
            }
            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(["All Goals", "In Progress", "High Priority", "Completed"], id: \.self) { value in FilterChip(title: value, selected: filter == value) { filter = value } } } }
            ForEach(goals) { goal in
                Button { editing = goal } label: {
                    HarborCard {
                        HStack { IconTile(symbol: goal.symbol); VStack(alignment: .leading) { Text(goal.name).font(.headline); Text(store.data.accountName(goal.accountID)).font(.caption).foregroundStyle(.secondary) }; Spacer(); if goal.saved >= goal.target { Image(systemName: "checkmark.seal.fill").foregroundStyle(HarborStyle.teal) } }
                        HStack { MoneyLabel(cents: goal.saved, currency: store.data.currency(goal.accountID)); Text("/ \(store.format(goal.target, currency: store.data.currency(goal.accountID)))").font(.caption) }
                        ProgressView(value: Double(goal.saved), total: Double(max(1, goal.target))).tint(HarborStyle.blue)
                        Text(goal.saved >= goal.target ? "Fully funded" : "Target: \(goal.deadline.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                        Text("Tap to edit or allocate funds").font(.caption).foregroundStyle(HarborStyle.blue)
                    }
                }.buttonStyle(.plain)
            }
            if goals.isEmpty { EmptyCard(title: "No goals here yet", detail: "Create a goal and choose an account to fund it.") }
            Button { creating = true } label: { Label("Create New Goal", systemImage: "plus.circle").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent)
            Text("Goal funds are earmarked within an account. Allocations do not change your net worth.").font(.caption).foregroundStyle(.secondary)
        }.sheet(item: $editing) { GoalEditor(existing: $0) }.sheet(isPresented: $creating) { GoalEditor() }
    }
}

// Charts use the selected ledger month rather than the static values in the exported mockups.
// Explicit tab names distinguish money already spent from a month-end estimate.
enum BudgetSpendingTab: String, CaseIterable, Identifiable {
    case current = "Current spending"
    case forecast = "Forecasted Spending"
    var id: String { rawValue }
}

struct ForecastExplanation: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("An estimate of your total spending by the end of the selected month.").font(.headline)
                    Text("Harbor combines your recorded spending with expected remaining expenses, using category amounts and payment dates from up to six prior months. At least two prior months are needed.")
                    Text("As you add October transactions, the estimate updates. Payroll is income, so it changes your balance but does not count as spending.")
                    Text("The planning range shows possible variation. It is not a guarantee or a confidence interval. Missing transactions, changed bills, and new habits can change the outcome.")
                    Text("Everything is calculated on this device. Your ledger, balances, and budget limits are unchanged by the forecast.")
                }.padding(24)
            }.navigationTitle("About Forecasted Spending").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

enum ChartMode: String, CaseIterable { case daily = "Daily Pace", cumulative = "Cumulative", prior = "vs. Prior", forecast = "Forecast" }
struct DayValue: Identifiable { var day: Int; var cents: Int; var id: Int { day } }
struct SpendingChart: View {
    @EnvironmentObject var store: HarborStore
    var mode: ChartMode
    private func series(_ month: Date, cumulative: Bool) -> [DayValue] {
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: month) ?? 1..<31
        let items = store.data.reportingEntries(in: month).filter { $0.kind == .expense }
        var total = 0
        return days.map { day in
            let value = items.filter { calendar.component(.day, from: $0.date) == day }.reduce(0) { $0 + $1.amount }
            total += value
            return DayValue(day: day, cents: cumulative ? total : value)
        }
    }
    var body: some View {
        let cumulative = mode != .daily
        let forecast = SpendingForecast.calculate(data: store.data, month: store.month)
        // Forecast mode stops the actual line at the latest recorded day and draws estimated days separately.
        let elapsed = forecast.observedThrough.map { Calendar.current.component(.day, from: $0) } ?? 0
        let points = series(store.month, cumulative: cumulative).filter { mode != .forecast || forecast.isHistorical || $0.day <= elapsed }
        Chart {
            ForEach(points) { point in
                if cumulative { LineMark(x: .value("Day", point.day), y: .value(store.data.reportingCurrency, Double(point.cents) / 100), series: .value("Series", "Selected month")).foregroundStyle(HarborStyle.blue).interpolationMethod(.monotone) }
                else { BarMark(x: .value("Day", point.day), y: .value(store.data.reportingCurrency, Double(point.cents) / 100)).foregroundStyle(HarborStyle.blue).cornerRadius(3) }
            }
            if mode == .prior {
                ForEach(series(Calendar.current.date(byAdding: .month, value: -1, to: store.month)!, cumulative: true)) { point in
                    LineMark(x: .value("Day", point.day), y: .value(store.data.reportingCurrency, Double(point.cents) / 100), series: .value("Series", "Prior month")).foregroundStyle(HarborStyle.teal).lineStyle(StrokeStyle(lineWidth: 2, dash: [4]))
                }
            }
            if mode == .forecast {
                ForEach(Array(forecast.curve.enumerated()), id: \.offset) { index, cents in
                    if !forecast.isHistorical && index + 1 >= max(1, elapsed) {
                        LineMark(x: .value("Day", index + 1), y: .value("Estimated " + store.data.reportingCurrency, Double(cents) / 100), series: .value("Series", "Forecast")).foregroundStyle(HarborStyle.teal).lineStyle(StrokeStyle(lineWidth: 2, dash: [4]))
                    }
                }
            }
        }.chartXAxisLabel("Day of month").chartYAxisLabel(store.data.reportingCurrency).accessibilityLabel("\(mode.rawValue) spending chart for \(store.month.formatted(.dateTime.month().year()))")
    }
}
struct AnalyticsScreen: View {
    @EnvironmentObject var store: HarborStore
    @State private var mode = ChartMode.cumulative
    @State private var sharePercent = true
    @State private var editingCategory: Category?
    var body: some View {
        Screen {
            MonthPicker()
            Picker("Chart view", selection: $mode) { ForEach(ChartMode.allCases.filter { $0 != .forecast }, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).accessibilityIdentifier("analytics.mode")
            HarborCard {
                Text("TOTAL OUTFLOW").font(.caption.bold())
                MoneyLabel(cents: store.data.total(.expense, in: store.month), size: 36)
                Text("Budget: \(store.format(store.monthlyBudget))").font(.caption).foregroundStyle(.secondary)
            }
            // Put ranked categories before detailed charts so they are easy to find.
            HarborCard {
                HStack { Text("Top Categories").font(.title3.bold()); Spacer(); Toggle("% share", isOn: $sharePercent).font(.caption).fixedSize() }
                Text("Ranked by spending in the selected month and currency. Unused categories, income, and linked transfers are excluded.").font(.caption).foregroundStyle(.secondary)
                if store.data.topCategories(in: store.month).isEmpty {
                    Text("No spending in this month. Choose another month or currency to see your top categories.").foregroundStyle(.secondary).accessibilityIdentifier("analytics.emptyCategories")
                }
                ForEach(store.data.topCategories(in: store.month)) { item in
                    let category = item.category
                    let share = Double(item.cents) / Double(max(1, store.data.total(.expense, in: store.month)))
                    Button { editingCategory = category } label: {
                        HStack { SymbolGlyph(symbol: category.symbol).foregroundStyle(HarborStyle.blue); Text(category.name).font(.subheadline); Spacer(); Text(sharePercent ? share.formatted(.percent.precision(.fractionLength(1))) : store.format(item.cents)).font(.subheadline).monospacedDigit(); Image(systemName: "pencil").font(.caption) }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("analytics.category." + category.name)
                    ProgressView(value: share).tint(HarborStyle.blue)
                }
                NavigationLink("Manage categories") { CategoryManagementScreen() }
                ShareLink(item: report) { Label("Export Report", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
            }
            HarborCard { Text("Trajectory Curve").font(.title3.bold()); SpendingChart(mode: mode).frame(height: 240); if mode == .prior { Text("Blue: selected month · Teal dashed: prior month").font(.caption) }; Text("Explore month-to-month trends. Your month-end estimate is in Budget → Forecasted Spending.").font(.caption).foregroundStyle(.secondary) }
            HarborCard {
                Text("Weekly Run Rate").font(.title3.bold())
                ForEach(0..<5, id: \.self) { week in
                    let amount = store.data.reportingEntries(in: store.month).filter { $0.kind == .expense && (Calendar.current.component(.day, from: $0.date) - 1) / 7 == week }.reduce(0) { $0 + $1.amount }
                    HStack { Text("Week \(week + 1)"); Spacer(); MoneyLabel(cents: amount, size: 17) }
                }
            }
        }.navigationTitle("Spending Analytics").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingCategory) { CategoryEditor(existing: $0) }
    }
    private var report: String {
        var lines = ["Harbor · \(store.month.formatted(.dateTime.month(.wide).year())) · \(store.data.reportingCurrency)", "Income: \(store.format(store.data.total(.income, in: store.month)))", "Outflow: \(store.format(store.data.total(.expense, in: store.month)))", "Budget: \(store.format(store.monthlyBudget))"]
        lines += store.data.topCategories(in: store.month).map { "\($0.category.name): \(store.format($0.cents))" }
        return lines.joined(separator: "\n")
    }
}

// Explain the evidence alongside the estimate so sparse or stale ledgers cannot imply certainty.
struct ForecastCard: View {
    @EnvironmentObject var store: HarborStore
    let forecast: SpendingForecast
    var body: some View {
        HarborCard {
            Text(forecast.isHistorical ? "Recorded month total" : "Month-end forecast").font(.title3.bold())
            if let estimate = forecast.estimate {
                MoneyLabel(cents: estimate, size: 32).accessibilityIdentifier("forecast.total")
                if !forecast.isHistorical {
                    Text("Planning range: \(store.format(forecast.lower!)) – \(store.format(forecast.upper!))").font(.subheadline)
                    Text("Recorded: \(store.format(forecast.actual)) · Estimated remaining: \(store.format(estimate - forecast.actual))").font(.caption)
                    Text("\(forecast.historyMonths) prior months · \(forecast.usesRecentWeights ? "recent months weighted more" : "equal month weights") · calculated on device").font(.caption)
                    DisclosureGroup("Model details") {
                        VStack(alignment: .leading, spacing: 12) {
                    Text("Category amounts and payment days are learned from up to six prior months. The range is a planning guide, not a confidence interval.").font(.caption)
                    if let error = forecast.meanAbsoluteError, let baseline = forecast.baselineError {
                        Text("Model-selection check: average error \(store.format(error)) across \(forecast.backtestMonths) held-back months. Last-month baseline: \(store.format(baseline)). Checks predict full months and do not prove October accuracy.").font(.caption)
                    } else {
                        Text("Not enough history for a historical accuracy check.").font(.caption)
                    }
                        }.padding(.top, 8)
                    }
                    // Keep detailed category estimates expandable so the trajectory remains easy to reach.
                    DisclosureGroup("Forecast by category") {
                        VStack(spacing: 12) {
                            ForEach(forecast.categories.sorted { $0.total > $1.total }.filter { $0.total > 0 }) { item in
                                HStack {
                                    Text(store.data.category(item.id)?.name ?? "Unknown category").font(.subheadline)
                                    Spacer()
                                    Text(store.format(item.total)).font(.subheadline).monospacedDigit()
                                }
                            }
                        }.padding(.top, 8)
                    }
                    ForEach(forecast.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                } else {
                    Text("Recorded expenses only; this is not a retrospective prediction.").font(.caption)
                }
            } else {
                Text("Import at least two prior months to estimate spending. A first month starting after day 1 is excluded because it may be incomplete.").font(.subheadline)
            }
        }
    }
}

// Home and Activity share compact month navigation; planning screens retain full-width controls.
private struct CompactMonthPicker: View {
    @EnvironmentObject var store: HarborStore
    var body: some View {
        HStack(spacing: 0) {
            Button { store.shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Previous month")
            Text(store.month.formatted(.dateTime.month(.abbreviated).year())).font(.caption.bold()).fixedSize()
            Button { store.shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Next month")
        }.background(HarborStyle.surface, in: Capsule())
    }
}

private struct HomeSquareCard<Content: View>: View {
    @ViewBuilder var content: Content
    // Scale the whole square with Dynamic Type to keep labels legible in horizontal grids.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 170
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(12).frame(width: side, height: side, alignment: .topLeading)
            .background(HarborStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(HarborStyle.navy)
    }
}

private struct HomeWeeklySpending: View {
    @EnvironmentObject var store: HarborStore
    @State private var selected: SpendingWeek?
    private var weeks: [SpendingWeek] { SpendingWeek.calculate(data: store.data, month: store.month) }
    var body: some View {
        HarborCard {
            Text("Weekly Spending").font(.headline)
            Text("Tap a bar for a daily breakdown").font(.caption).foregroundStyle(.secondary)
            // Each entire column is a button, including zero-spend weeks and VoiceOver targets.
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    Button { selected = week } label: {
                        VStack(spacing: 6) {
                            Text(store.format(week.total)).font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
                            VStack { Spacer(minLength: 0); RoundedRectangle(cornerRadius: 5).fill(HarborStyle.blue).frame(height: max(5, 110 * Double(week.total) / Double(max(1, weeks.map(\.total).max() ?? 1)))) }.frame(height: 110)
                            Text("\(index + 1)").font(.caption.bold())
                            Text(week.days.first!.formatted(.dateTime.month(.abbreviated).day())).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                        }.frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Week \(index + 1), starting \(week.days.first!.formatted(date: .abbreviated, time: .omitted)), \(store.format(week.total)). Show daily summary")
                        .accessibilityIdentifier("home.week.\(index)")
                }
            }
            Text("\(store.data.reportingCurrency) · Calendar weeks; only days in this month").font(.caption2).foregroundStyle(.secondary)
        }.sheet(item: $selected) { week in WeeklySpendingSummary(week: week) }
    }
}

private struct WeeklySpendingSummary: View {
    @EnvironmentObject var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    let week: SpendingWeek
    private var busiest: Date? { week.days.filter { !week.entries(on: $0).isEmpty }.max { total($0) < total($1) } }
    private func total(_ day: Date) -> Int { week.entries(on: day).reduce(0) { $0 + $1.amount } }
    var body: some View {
        NavigationStack {
            List {
                Section("Week overview") {
                    Text("\(week.days.first!.formatted(date: .abbreviated, time: .omitted)) – \(week.days.last!.formatted(date: .abbreviated, time: .omitted))").font(.headline)
                    LabeledContent("Total spent", value: store.format(week.total))
                    LabeledContent("Daily average", value: store.format(week.total / max(1, week.days.count)))
                    LabeledContent("Purchases", value: "\(week.entries.count)")
                    if let busiest { LabeledContent("Highest spending day", value: busiest.formatted(.dateTime.weekday(.wide))) }
                    Text("\(store.data.reportingCurrency) expenses only. Transfers excluded. Weeks at month boundaries show only days in the selected month.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(week.days, id: \.self) { day in
                    Section(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                        LabeledContent("Spent", value: store.format(total(day))).font(.headline)
                        if week.entries(on: day).isEmpty { Text("No spending recorded").foregroundStyle(.secondary) }
                        // Aggregate categories and show purchases to make daily habits inspectable.
                        ForEach(categoryIDs(day), id: \.self) { id in
                            LabeledContent(store.data.category(id)?.name ?? "Uncategorized", value: store.format(week.entries(on: day).filter { $0.categoryID == id }.reduce(0) { $0 + $1.amount })).font(.subheadline)
                        }
                        ForEach(week.entries(on: day).sorted { $0.date < $1.date }) { entry in
                            HStack { VStack(alignment: .leading) { Text(entry.merchant); Text(store.data.accountName(entry.accountID)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(store.format(entry.amount)) }.font(.subheadline)
                        }
                    }
                }
            }.navigationTitle("Weekly summary").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func categoryIDs(_ day: Date) -> [UUID] {
        Array(Set(week.entries(on: day).map(\.categoryID))).sorted { (store.data.category($0)?.name ?? "") < (store.data.category($1)?.name ?? "") }
    }
}
