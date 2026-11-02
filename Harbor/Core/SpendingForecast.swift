import Foundation

// Forecasts are derived in memory from the local ledger; they never modify or persist transactions.
struct SpendingForecast {
    struct CategoryEstimate: Identifiable {
        let id: UUID
        let actual: Int
        let remaining: Int
        var total: Int { actual + remaining }
    }
    let actual: Int
    let estimate: Int?
    let lower: Int?
    let upper: Int?
    let observedThrough: Date?
    let historyMonths: Int
    let backtestMonths: Int
    let meanAbsoluteError: Int?
    let baselineError: Int?
    let usesRecentWeights: Bool
    let isHistorical: Bool
    let categories: [CategoryEstimate]
    let curve: [Int]
    let warnings: [String]

    static func calculate(data: FinanceData, month: Date, now: Date = Date(), calendar: Calendar = .current) -> SpendingForecast {
        let start = calendar.dateInterval(of: .month, for: month)!.start
        let current = calendar.dateInterval(of: .month, for: now)!.start
        let days = calendar.range(of: .day, in: .month, for: start)!.count
        let cutoff = calendar.startOfDay(for: now)
        // Future-dated records cannot leak into training, current actuals, or historical validation.
        let available = data.transactions.filter { calendar.startOfDay(for: $0.date) <= cutoff && data.currency($0.accountID) == data.reportingCurrency && !$0.isTransfer }
        let selected = available.filter { calendar.isDate($0.date, equalTo: start, toGranularity: .month) }
        let expenses = selected.filter { $0.kind == .expense }
        let actual = expenses.reduce(0) { $0 + $1.amount }
        let historical = start < current
        let observed = selected.map(\.date).max()
        let elapsed = historical ? days : observed.map { calendar.component(.day, from: $0) } ?? 0
        let grouped = Dictionary(grouping: available.filter { $0.date < min(start, current) }) {
            calendar.dateInterval(of: .month, for: $0.date)!.start
        }
        // Exclude a visibly truncated first month and missing months; absence is not proof of zero spending.
        let first = available.map(\.date).min()
        let history = grouped.keys.sorted().filter { key in
            guard let first, calendar.isDate(first, equalTo: key, toGranularity: .month) else { return true }
            return calendar.component(.day, from: first) == 1
        }.suffix(6)
        let months = Array(history)
        func rows(_ keys: [Date]) -> [[Transaction]] {
            keys.map { (grouped[$0] ?? []).filter { $0.kind == .expense } }
        }
        let samples = rows(months)
        func average(_ values: [Int], recent: Bool) -> Int {
            guard !values.isEmpty else { return 0 }
            let weights = values.indices.map { recent ? Double($0 + 1) : 1 }
            return Int((zip(values, weights).reduce(0.0) { $0 + Double($1.0) * $1.1 } / weights.reduce(0, +)).rounded())
        }
        // Rolling-origin checks only train on earlier months. They measure full-month forecasts, not mid-month accuracy.
        var weightedErrors: [Int] = [], meanErrors: [Int] = [], naiveErrors: [Int] = []
        if months.count >= 4 {
            for index in 2..<months.count {
                let training = samples[..<index].map { $0.reduce(0) { $0 + $1.amount } }
                let truth = samples[index].reduce(0) { $0 + $1.amount }
                weightedErrors.append(abs(average(training, recent: true) - truth))
                meanErrors.append(abs(average(training, recent: false) - truth))
                naiveErrors.append(abs(training.last! - truth))
            }
        }
        let useRecent = weightedErrors.isEmpty || average(weightedErrors, recent: false) <= average(meanErrors, recent: false)
        let errors = useRecent ? weightedErrors : meanErrors
        let enough = months.count >= 2
        var warnings = ["Assumes imported months are complete. Missing transactions and accounts can lower this estimate.", "Bill reminders are not added separately; past bill payments are already part of the learned pattern."]
        if let first = months.first, let last = months.last {
            warnings.append("History used: \(first.formatted(.dateTime.month(.wide).year())) through \(last.formatted(.dateTime.month(.wide).year())).")
        }
        if data.isDemo { warnings.insert("Sample data — this is not your personal forecast.", at: 0) }
        if !historical && elapsed == 0 { warnings.insert("No recorded transactions for this month. Estimate uses history only, not assumed zero spending so far.", at: 0) }
        if !historical, let observed, calendar.startOfDay(for: observed) < cutoff {
            warnings.insert("Records through \(observed.formatted(date: .abbreviated, time: .omitted)); later spending is estimated.", at: 0)
        }
        if let latest = months.last, let preceding = calendar.date(byAdding: .month, value: -1, to: start), latest < preceding {
            warnings.append("Recent history is missing. This estimate may be stale.")
        }
        if start > current { warnings.append("Future month estimate assumes recent patterns continue; it does not model seasonality or inflation.") }
        // Bucket once, then use prefix sums; forecast cost stays bounded for large imported ledgers.
        let profiles: [[UUID: [Int]]] = samples.map { sample in
            var buckets: [UUID: [Int]] = [:]
            for row in sample {
                let day = min(calendar.component(.day, from: row.date), days)
                buckets[row.categoryID, default: Array(repeating: 0, count: days + 1)][day] += row.amount
            }
            for id in Array(buckets.keys) {
                for day in 1...days { buckets[id]![day] += buckets[id]![day - 1] }
            }
            return buckets
        }
        let actualByCategory = Dictionary(grouping: expenses, by: \.categoryID).mapValues { $0.reduce(0) { $0 + $1.amount } }
        func predicted(_ category: UUID, through day: Int) -> Int {
            average(profiles.map { profile in
                guard let values = profile[category] else { return 0 }
                return values[day] - values[elapsed]
            }, recent: useRecent)
        }
        let estimates = data.reportingCategories.map { category in
            CategoryEstimate(id: category.id, actual: actualByCategory[category.id] ?? 0,
                             remaining: historical || !enough ? 0 : predicted(category.id, through: days))
        }
        let total = historical ? actual : enough ? estimates.reduce(0) { $0 + $1.total } : nil
        // This is a planning band, not a calibrated confidence interval. Preserve a minimum uncertainty floor.
        let remainingSamples = samples.map { sample in
            sample.filter { min(calendar.component(.day, from: $0.date), days) > elapsed }.reduce(0) { $0 + $1.amount }
        }
        let remaining = estimates.reduce(0) { $0 + $1.remaining }
        let deviations = remainingSamples.map { abs($0 - remaining) }
        let width = max(Int((Double(remaining) * 0.2).rounded()), average(deviations, recent: false), average(errors, recent: false))
        var running = 0
        let actualByDay = Dictionary(grouping: expenses) { calendar.component(.day, from: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        var curve = (1...days).map { day -> Int in
            if day <= elapsed {
                running += actualByDay[day] ?? 0
                return running
            }
            // Cumulative category rounding keeps the chart endpoint equal to the category/overall estimate.
            return actual + data.reportingCategories.reduce(0) { $0 + predicted($1.id, through: day) }
        }
        if !enough && !historical { curve = [] }
        return SpendingForecast(actual: actual, estimate: total,
                                lower: total.map { historical ? $0 : max(actual, $0 - width) },
                                upper: total.map { historical ? $0 : $0 + width },
                                observedThrough: observed, historyMonths: months.count,
                                backtestMonths: errors.count, meanAbsoluteError: errors.isEmpty ? nil : average(errors, recent: false),
                                baselineError: naiveErrors.isEmpty ? nil : average(naiveErrors, recent: false),
                                usesRecentWeights: useRecent, isHistorical: historical, categories: estimates,
                                curve: curve, warnings: warnings)
    }
}
