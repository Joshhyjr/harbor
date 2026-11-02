import Foundation
import PDFKit
import Vision
import CoreGraphics

// PDFKit text order is not table order. Read positioned words and reconcile every transaction.
enum StatementPDFImport {
    private struct Word { var text: String; var box: CGRect }
    static func parse(_ bytes: Data) throws -> ImportBatch {
        guard bytes.count <= TransactionImport.maximumBytes, let document = PDFDocument(data: bytes), !document.isLocked,
              document.pageCount > 0, document.pageCount <= 100 else {
            throw FinanceError(message: "Choose an unlocked PDF of 1–100 pages, no larger than 25 MB.")
        }
        // Separate category/method tables use calendar dates and may span continuation pages.
        let hasSeparateColumns = (0..<document.pageCount).contains { index in
            guard let text = document.page(at: index)?.string else { return false }
            return text.range(of: #"(?i)Date\s+Description\s+Category\s+Method\s+Money\s+(In|Out)"#, options: .regularExpression) != nil
        }
        if hasSeparateColumns { return try parseColumnTable(document) }
        var batch = ImportBatch(rows: [])
        var monthCount = 0, currentMonth = "", expectedMonthCount = 0
        var expectedIncome: Int?, expectedExpenses: Int?
        var detectedCurrency: String?
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw issue(index, "Page could not be opened.") }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { throw issue(index, "Invalid page dimensions.") }
            let raw = page.string ?? ""
            guard raw.utf8.count <= 2_000_000 else { throw issue(index, "Page text exceeds the import limit.") }
            let words: [Word]
            let text: String
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
                words = try recognize(page)
                // OCR text is used only as data; document prose never becomes executable instructions.
                text = orderedText(words)
                batch.usedOCR = true
            } else {
                text = raw
                let ns = raw as NSString
                words = matches(#"\S+"#, raw).compactMap { match in
                    guard let selection = page.selection(for: match.range) else { return nil }
                    let rect = selection.bounds(for: page)
                    guard rect.width > 0, rect.height > 0 else { return nil }
                    return Word(text: ns.substring(with: match.range), box: rect)
                }
            }
            guard words.count <= 50_000 else { throw issue(index, "Page text exceeds the import limit.") }
            if let currency = try Currency.detect(text) {
                guard detectedCurrency == nil || detectedCurrency == currency else { throw issue(index, "Multiple statement currencies were found.") }
                detectedCurrency = currency
            }
            func summary(_ label: String) -> Int? {
                // Labels and amounts can be separated in extraction order, so use their page positions.
                let parts = label.components(separatedBy: " ")
                guard let start = words.first(where: { $0.text.uppercased() == parts[0] }),
                      let end = words.first(where: { $0.text.uppercased() == parts.last! && abs($0.box.midY - start.box.midY) < 5 }) else { return nil }
                let left = start.box.minX - 5, right = max(end.box.maxX + 25, start.box.minX + bounds.width * 0.20)
                return words.filter { $0.box.minX >= left && $0.box.maxX <= right && $0.box.midY < start.box.minY && $0.box.midY > start.box.minY - 35 }
                    .sorted { $0.box.midY > $1.box.midY }.compactMap { TransactionImport.cents($0.text) }.first
            }
            let dateWords = words.filter { $0.text.range(of: #"^\d{2}-\d{2}$"#, options: .regularExpression) != nil }.sorted { $0.box.midY > $1.box.midY }
            if dateWords.isEmpty {
                guard index == 0, document.pageCount > 1, let opening = summary("OPENING BALANCE"), let closing = summary("CLOSING BALANCE"),
                      let incoming = summary("DEPOSITS"), let expenses = summary("WITHDRAWALS") else { throw issue(index, "No supported transaction table was found. Export CSV if your statement has a different layout.") }
                batch.openingBalance = opening; batch.closingBalance = closing
                expectedIncome = incoming; expectedExpenses = expenses
                continue
            }
            guard let monthMatch = matches(#"(?i)\b(JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s+(20\d{2})\b"#, text).first else { throw issue(index, "A month and year are required above the table.") }
            let ns = text as NSString
            let monthName = ns.substring(with: monthMatch.range(at: 1)).uppercased(), year = ns.substring(with: monthMatch.range(at: 2))
            let month = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"].firstIndex(of: monthName)! + 1
            let monthKey = "\(year)-\(month)"
            if monthKey != currentMonth {
                guard currentMonth.isEmpty || monthCount == expectedMonthCount else { throw issue(index, "The previous month's table is incomplete.") }
                currentMonth = monthKey; monthCount = 0
                guard let opening = summary("OPENING BALANCE") else { throw issue(index, "The monthly opening balance is missing.") }
                if batch.rows.isEmpty {
                    guard batch.openingBalance == nil || batch.openingBalance == opening else { throw issue(index, "Opening balances disagree.") }
                    batch.openingBalance = opening
                } else if batch.rows.last?.balance != opening { throw issue(index, "Monthly balances do not connect.") }
            }
            guard let out = words.first(where: { $0.text.uppercased() == "OUT" }),
                  let incoming = words.first(where: { $0.text.uppercased() == "IN" && abs($0.box.midY - out.box.midY) < 5 }),
                  let balance = words.first(where: { $0.text.uppercased() == "BALANCE" && abs($0.box.midY - out.box.midY) < 5 }),
                  let description = words.first(where: { $0.text.uppercased() == "DESCRIPTION" || $0.text.uppercased() == "DESCRIPTION / CATEGORY" }),
                  out.box.maxX < incoming.box.maxX, incoming.box.maxX < balance.box.maxX else {
                throw issue(index, "Expected Date, Description / Category, Money Out, Money In, and Balance columns.")
            }
            let expenseEnd = out.box.maxX + (incoming.box.maxX - out.box.maxX) * 0.15
            let incomeEnd = incoming.box.maxX + (balance.box.maxX - incoming.box.maxX) * 0.15
            let moneyStart = out.box.minX - bounds.width * 0.10
            for dateWord in dateWords {
                // Large rotated watermarks intersect rows but are not table-cell text.
                let line = words.filter { abs($0.box.midY - dateWord.box.midY) < dateWord.box.height * 0.8 && $0.box.height <= dateWord.box.height * 1.4 }
                let merchant = line.filter { $0.box.minX >= description.box.minX - 2 && $0.box.maxX < moneyStart }.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
                let amounts = line.filter {
                    ($0.text.contains("$") || $0.text.contains("£") || $0.text.contains("€")) || (batch.usedOCR && $0.box.minX > moneyStart && $0.text.range(of: #"^-?[0-9,]+\.[0-9]{2}$"#, options: .regularExpression) != nil)
                }
                func amount(_ left: CGFloat, _ right: CGFloat) throws -> Int? {
                    let cells = amounts.filter { $0.box.midX >= left && $0.box.midX < right }
                    guard cells.count <= 1 else { throw issue(index, "Ambiguous amount cells.") }
                    guard let cell = cells.first else { return nil }
                    guard let cents = TransactionImport.cents(cell.text) else { throw issue(index, "An amount could not be read exactly.") }
                    return cents
                }
                let debit = try amount(moneyStart, expenseEnd), credit = try amount(expenseEnd, incomeEnd)
                let running = try amount(incomeEnd, bounds.maxX)
                guard (debit != nil) != (credit != nil), let value = debit ?? credit, value > 0, let running, !merchant.isEmpty,
                      dateWord.text.hasPrefix(String(format: "%02d-", month)), let day = TransactionImport.date("\(year)-\(dateWord.text)") else { throw issue(index, "A transaction row is incomplete or ambiguous at \(dateWord.text). Export CSV instead.") }
                let detailY = dateWord.box.midY - dateWord.box.height * 1.1
                let detail = words.filter { abs($0.box.midY - detailY) < dateWord.box.height * 0.5 && $0.box.height <= dateWord.box.height * 1.1 && $0.box.minX >= description.box.minX - 2 && $0.box.maxX < moneyStart }.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
                var parts = detail.components(separatedBy: CharacterSet(charactersIn: "·•"))
                // OCR may omit a small bullet; an exact known payment-method suffix is still unambiguous.
                if parts.count == 1, batch.usedOCR {
                    for method in ["E-TRANSFER", "PRE-AUTH", "DIRECT DEP", "CARD", "DEBIT", "TAP", "FEE"] where detail.hasSuffix(" " + method) {
                        parts = [String(detail.dropLast(method.count + 1)), method]
                        break
                    }
                }
                guard parts.count == 2, !parts[0].trimmingCharacters(in: .whitespaces).isEmpty else { throw issue(index, "A category / payment method could not be read at \(dateWord.text).") }
                guard batch.rows.count < TransactionImport.maximumRows else { throw issue(index, "PDF exceeds 10,000 transactions.") }
                batch.rows.append(ImportRow(date: day, merchant: merchant, amount: value, kind: credit == nil ? .expense : .income,
                                           category: parts[0].trimmingCharacters(in: .whitespaces), note: parts[1].trimmingCharacters(in: .whitespaces), balance: running))
            }
            monthCount += dateWords.count
            guard let footer = matches(#"(\d+)\s*/\s*(\d+)\s+entries shown"#, text).first,
                  let shown = Int(ns.substring(with: footer.range(at: 1))), let total = Int(ns.substring(with: footer.range(at: 2))), shown == monthCount else {
                throw issue(index, "The statement's transaction count does not match the extracted rows.")
            }
            expectedMonthCount = total
        }
        batch.currencyCode = detectedCurrency
        for i in batch.rows.indices { batch.rows[i].currencyCode = detectedCurrency }
        guard monthCount == expectedMonthCount else { throw FinanceError(message: "The last month's statement is incomplete.") }
        if batch.closingBalance == nil { batch.closingBalance = batch.rows.last?.balance }
        try TransactionImport.validate(batch)
        guard expectedIncome == nil || batch.income == expectedIncome, expectedExpenses == nil || batch.expenses == expectedExpenses else {
            throw FinanceError(message: "Statement totals do not match the extracted transactions. Export CSV instead.")
        }
        return batch
    }
    // Read column positions, wrapped descriptions, and continuation pages without trusting PDF text order.
    private static func parseColumnTable(_ document: PDFDocument) throws -> ImportBatch {
        var batch = ImportBatch(rows: [])
        var year: String?
        var expectedCount: Int?, expectedIncome: Int?
        var declaredClosing: Int?
        var monthlyCount = 0, expectedMonthlyCount: Int?, currentMonth: String?
        var monthlyIncome: Int?, monthlyOut: Int?, monthlyClosing: Int?
        var monthlyRows: [ImportRow] = []
        var detectedCurrency: String?
        func finishMonth() throws {
            guard let count = expectedMonthlyCount else { return }
            guard monthlyCount == count, monthlyRows.filter({ $0.kind == .income }).reduce(0, { $0 + $1.amount }) == monthlyIncome,
                  monthlyRows.filter({ $0.kind == .expense }).reduce(0, { $0 + $1.amount }) == monthlyOut,
                  monthlyRows.last?.balance == monthlyClosing else { throw FinanceError(message: "PDF monthly counts or totals do not reconcile. No transactions were imported.") }
        }
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw issue(index, "Page could not be opened.") }
            let bounds = page.bounds(for: .mediaBox)
            let raw = page.string ?? ""
            guard raw.utf8.count <= 2_000_000 else { throw issue(index, "Page text exceeds the import limit.") }
            let words: [Word], text: String
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
                words = try recognize(page); text = orderedText(words); batch.usedOCR = true
            } else {
                let ns = raw as NSString
                words = matches(#"\S+"#, raw).compactMap { match in
                    guard let selection = page.selection(for: match.range) else { return nil }
                    return Word(text: ns.substring(with: match.range), box: selection.bounds(for: page))
                }
                text = raw
            }
            guard words.count <= 50_000 else { throw issue(index, "Page text exceeds the import limit.") }
            if let currency = try Currency.detect(text) {
                guard detectedCurrency == nil || detectedCurrency == currency else { throw issue(index, "Multiple statement currencies were found.") }
                detectedCurrency = currency
            }
            let ns = text as NSString
            if let month = matches(#"(?i)\b(JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s+(20\d{2})\b"#, text).first {
                let nextMonth = ns.substring(with: month.range(at: 1)).uppercased()
                if currentMonth != nextMonth {
                    try finishMonth()
                    currentMonth = nextMonth; monthlyCount = 0; monthlyRows = []
                    expectedMonthlyCount = nil; monthlyIncome = nil; monthlyOut = nil; monthlyClosing = nil
                    year = ns.substring(with: month.range(at: 2))
                    // Optional published monthly totals include every debit, including savings transfers.
                    if let summary = matches(#"(?i)(\d+) transactions\s*\|\s*Money in\s+([\$£€][\d,]+\.\d{2})\s*\|\s*Money out\s+([\$£€][\d,]+\.\d{2})\s*\|\s*End balance\s+([\$£€][\d,]+\.\d{2})"#, text).first {
                        expectedMonthlyCount = Int(ns.substring(with: summary.range(at: 1)))
                        monthlyIncome = TransactionImport.cents(ns.substring(with: summary.range(at: 2)))
                        monthlyOut = TransactionImport.cents(ns.substring(with: summary.range(at: 3)))
                        monthlyClosing = TransactionImport.cents(ns.substring(with: summary.range(at: 4)))
                    }
                }
            }
            guard let header = words.first(where: { $0.text.caseInsensitiveCompare("Date") == .orderedSame }),
                  let description = words.first(where: { $0.text.caseInsensitiveCompare("Description") == .orderedSame && abs($0.box.midY - header.box.midY) < 5 }) else {
                // A summary page can be skipped only when it supplies independently checked statement anchors.
                guard index == 0, let count = matches(#"(\d+) (?:fictional )?transactions"#, text).first else { throw issue(index, "No recognizable transaction table was found.") }
                expectedCount = Int(ns.substring(with: count.range(at: 1)))
                func summaryAmount(_ first: String, _ last: String) -> Int? {
                    guard let start = words.first(where: { $0.text.uppercased() == first }),
                          let end = words.first(where: { $0.text.uppercased() == last && abs($0.box.midY - start.box.midY) < 5 }) else { return nil }
                    return words.filter { $0.box.minX >= start.box.minX - 3 && $0.box.minX < end.box.maxX + 30 && $0.box.midY < start.box.minY && $0.box.midY > start.box.minY - 35 }
                        .sorted { $0.box.midY > $1.box.midY }.compactMap { TransactionImport.cents($0.text) }.first
                }
                batch.openingBalance = summaryAmount("OPENING", "BALANCE")
                declaredClosing = summaryAmount("CLOSING", "BALANCE")
                expectedIncome = summaryAmount("TOTAL", "IN")
                guard batch.openingBalance != nil, declaredClosing != nil else { throw issue(index, "Summary balances could not be read exactly.") }
                continue
            }
            func heading(_ name: String) -> Word? { words.first { $0.text.caseInsensitiveCompare(name) == .orderedSame && abs($0.box.midY - header.box.midY) < 5 } }
            guard let category = heading("Category"), let method = heading("Method"), let incoming = heading("In"), let outgoing = heading("Out"), let balance = heading("Balance"), let year else {
                throw issue(index, "Expected Date, Description, Category, Method, Money In, Money Out, Balance, and a year.")
            }
            let moneyHeaders = words.filter { $0.text.caseInsensitiveCompare("Money") == .orderedSame && abs($0.box.midY - header.box.midY) < 5 }.sorted { $0.box.minX < $1.box.minX }
            guard moneyHeaders.count == 2, description.box.minX < category.box.minX, category.box.minX < method.box.minX,
                  method.box.minX < moneyHeaders[0].box.minX, moneyHeaders[1].box.minX < balance.box.minX else { throw issue(index, "Ambiguous table columns.") }
            let anchors = words.filter { abs($0.box.minX - header.box.minX) < 5 && $0.box.midY < header.box.minY && $0.text.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil }.sorted { $0.box.midY > $1.box.midY }
            guard !anchors.isEmpty else { throw issue(index, "The transaction table is empty or unreadable.") }
            let footer = words.filter { $0.text.uppercased() == "MONTH" && $0.box.midY < anchors.last!.box.midY }.map { $0.box.maxY }.max() ?? 38
            for (rowIndex, anchor) in anchors.enumerated() {
                let top = rowIndex == 0 ? header.box.minY : (anchors[rowIndex - 1].box.midY + anchor.box.midY) / 2
                let bottom = rowIndex + 1 < anchors.count ? (anchor.box.midY + anchors[rowIndex + 1].box.midY) / 2 : footer
                let row = words.filter { $0.box.midY < top && $0.box.midY > bottom }
                func field(_ left: CGFloat, _ right: CGFloat) -> String {
                    let cells = row.filter { $0.box.minX >= left - 2 && $0.box.minX < right - 2 }
                    // Baselines vary slightly between fonts; group by vertical bands before sorting horizontally.
                    return orderedText(cells).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                }
                let dateText = field(header.box.minX, description.box.minX)
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "dd MMM yyyy"; formatter.isLenient = false
                guard let date = formatter.date(from: dateText + " " + year) else { throw issue(index, "An ambiguous transaction date was found.") }
                func amount(_ left: CGFloat, _ right: CGFloat) throws -> Int? {
                    let cells = row.filter { $0.box.maxX > left && $0.box.maxX <= right + 2 && (($0.text.contains("$") || $0.text.contains("£") || $0.text.contains("€")) || $0.text.range(of: #"^-?[\d,]+\.\d{2}$"#, options: .regularExpression) != nil) }
                    guard cells.count <= 1 else { throw issue(index, "Ambiguous amount cells.") }
                    guard let cell = cells.first else { return nil }
                    guard let value = TransactionImport.cents(cell.text) else { throw issue(index, "An amount could not be read exactly.") }
                    return value
                }
                let firstMoney = moneyHeaders[0].box.minX, secondMoney = moneyHeaders[1].box.minX
                let first = try amount(firstMoney - 3, secondMoney - 3), second = try amount(secondMoney - 3, balance.box.minX - 3)
                let credit = incoming.box.minX < outgoing.box.minX ? first : second
                let debit = incoming.box.minX < outgoing.box.minX ? second : first
                guard (credit ?? 0) >= 0, (debit ?? 0) >= 0, ((credit ?? 0) > 0) != ((debit ?? 0) > 0), let running = try amount(balance.box.minX - 3, bounds.maxX), let value = (credit ?? 0) > 0 ? credit : debit, value > 0 else { throw issue(index, "A financial row is incomplete or ambiguous.") }
                let merchant = field(description.box.minX, category.box.minX)
                let label = field(category.box.minX, method.box.minX)
                // PDFKit can join an empty money-cell dash to the last method word.
                let paymentMethod = field(method.box.minX, firstMoney).trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                guard !merchant.isEmpty, !label.isEmpty else { throw issue(index, "A description or category is missing.") }
                let entry = ImportRow(date: date, merchant: merchant, amount: value, kind: credit == nil || credit == 0 ? .expense : .income, category: label, note: paymentMethod, balance: running)
                batch.rows.append(entry); monthlyRows.append(entry); monthlyCount += 1
                guard batch.rows.count <= TransactionImport.maximumRows else { throw issue(index, "PDF exceeds 10,000 transactions.") }
            }
        }
        try finishMonth()
        batch.currencyCode = detectedCurrency
        for i in batch.rows.indices { batch.rows[i].currencyCode = detectedCurrency }
        guard expectedCount == nil || expectedCount == batch.rows.count else { throw FinanceError(message: "PDF currency or transaction count could not be reconciled.") }
        if batch.openingBalance == nil, let first = batch.rows.first, let running = first.balance { batch.openingBalance = running - first.signedAmount }
        batch.closingBalance = declaredClosing ?? batch.rows.last?.balance
        try TransactionImport.validate(batch)
        guard expectedIncome == nil || batch.income == expectedIncome else { throw FinanceError(message: "PDF deposit totals do not reconcile.") }
        return batch
    }
    private static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern).matches(in: text, range: NSRange(text.startIndex..., in: text))) ?? []
    }
    private static func issue(_ page: Int, _ message: String) -> FinanceError { FinanceError(message: "PDF page \(page + 1): \(message)") }
    private static func orderedText(_ words: [Word]) -> String {
        var lines: [[Word]] = []
        for word in words.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = lines.indices.last, abs(lines[last][0].box.midY - word.box.midY) < 4 { lines[last].append(word) }
            else { lines.append([word]) }
        }
        return lines.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }.joined(separator: "\n")
    }
    private static func recognize(_ page: PDFPage) throws -> [Word] {
        // OCR stays on-device. Render one page at a time to bound memory, then reuse the same table rules.
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { throw FinanceError(message: "PDF page has invalid dimensions.") }
        let scale = min(3, 2400 / max(bounds.width, bounds.height))
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw FinanceError(message: "Could not render PDF for OCR.") }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale); context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { throw FinanceError(message: "Could not render PDF for OCR.") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        var words: [Word] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            for match in matches(#"\S+"#, text) {
                guard let range = Range(match.range, in: text), let rect = try candidate.boundingBox(for: range)?.boundingBox else { continue }
                let box = CGRect(x: bounds.minX + rect.minX * bounds.width, y: bounds.minY + rect.minY * bounds.height,
                                 width: rect.width * bounds.width, height: rect.height * bounds.height)
                words.append(Word(text: String(text[range]), box: box))
            }
        }
        return words
    }
}

extension StatementPDFImport {
    // Keep exact embedded-text parsing first. OCR may broaden layouts, but cannot override failed financial checks.
    static func parseWithDocumentRecognition(_ bytes: Data) async throws -> ImportBatch {
        do { return try parse(bytes) }
        catch {
            let message = error.localizedDescription.lowercased()
            let unsupported = ["no supported transaction table", "no recognizable transaction table", "expected date", "a month and year are required"].contains { message.contains($0) }
            guard unsupported else { throw error }
            if #available(iOS 26.0, macOS 26.0, *) { return try await recognizeDocumentPDF(bytes) }
            throw FinanceError(message: "This PDF layout needs document recognition on iOS 26 or later, or a CSV export. " + error.localizedDescription)
        }
    }
    @available(iOS 26.0, macOS 26.0, *)
    static func recognizeDocumentPDF(_ bytes: Data) async throws -> ImportBatch {
        guard bytes.count <= TransactionImport.maximumBytes, let document = PDFDocument(data: bytes), !document.isLocked,
              document.pageCount > 0, document.pageCount <= 100 else { throw FinanceError(message: "Choose an unlocked PDF of 1–100 pages, no larger than 25 MB.") }
        var combined = ImportBatch(rows: [], usedOCR: true, usedDocumentRecognition: true)
        var contextCurrency: String?
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw issue(index, "Page is unreadable.") }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { throw issue(index, "Invalid page dimensions.") }
            let scale = min(3, 2200 / max(bounds.width, bounds.height))
            let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw issue(index, "Could not render page for document recognition.") }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale); context.translateBy(x: -bounds.minX, y: -bounds.minY)
            page.draw(with: .mediaBox, to: context)
            guard let image = context.makeImage() else { throw issue(index, "Could not render page.") }
            var request = RecognizeDocumentsRequest()
            request.textRecognitionOptions.useLanguageCorrection = false
            let observations = try await request.perform(on: image)
            let text = observations.map { $0.document.text.transcript }.joined(separator: "\n")
            if let currency = try Currency.detect(text) {
                guard contextCurrency == nil || currency == contextCurrency else { throw issue(index, "Multiple currencies were found.") }
                contextCurrency = currency
            }
            let tables = observations.flatMap { $0.document.tables }
            var recognized = false
            for table in tables {
                let cells = table.rows.map { $0.map { $0.content.text.transcript } }
                guard DocumentTableImport.recognizes(cells) else { continue }
                let batch = try DocumentTableImport.parse(cells, context: text, currency: contextCurrency)
                combined.rows.append(contentsOf: batch.rows); recognized = true
                guard combined.rows.count <= TransactionImport.maximumRows else { throw issue(index, "PDF exceeds 10,000 transactions.") }
            }
            // Do not silently omit an unrecognized page, including a summary whose controls we cannot validate.
            guard recognized else { throw issue(index, "Document recognition could not identify a complete transaction table. Export CSV or use a supported statement layout.") }
        }
        combined.currencyCode = contextCurrency
        for i in combined.rows.indices { combined.rows[i].currencyCode = contextCurrency }
        if let first = combined.rows.first, let balance = first.balance { combined.openingBalance = balance - first.signedAmount }
        combined.closingBalance = combined.rows.last?.balance
        try TransactionImport.validate(combined)
        return combined
    }
}

// Convert recognized cells through the same strict CSV/amount validation; numeric date order is never guessed.
enum DocumentTableImport {
    static func header(_ text: String) -> String {
        let key = text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        switch key {
        case "posting date", "date posted", "transaction date": return "date"
        case "payee", "merchant", "transaction details", "details": return "description"
        case "paid out", "withdrawals", "withdrawal", "money out", "debit": return "debit"
        case "paid in", "deposits", "deposit", "money in", "credit": return "credit"
        case "running balance": return "balance"
        case "method": return "payment method"
        default: return key
        }
    }
    static func recognizes(_ cells: [[String]]) -> Bool {
        guard let first = cells.first else { return false }
        let headers = first.map(header)
        return headers.contains("date") && headers.contains("description") && (headers.contains("amount") || (headers.contains("debit") && headers.contains("credit")))
    }
    static func parse(_ cells: [[String]], context: String, currency: String?) throws -> ImportBatch {
        guard recognizes(cells), let first = cells.first else { throw FinanceError(message: "Unrecognized transaction columns.") }
        let headers = first.map(header)
        guard let dateIndex = headers.firstIndex(of: "date"), let merchant = headers.firstIndex(of: "description") else { throw FinanceError(message: "Missing transaction columns.") }
        var output = [headers]
        let yearExpression = try NSRegularExpression(pattern: #"\b(20\d{2})\b"#)
        let ns = context as NSString
        let years = Set(yearExpression.matches(in: context, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) })
        for source in cells.dropFirst() {
            guard source.count == headers.count else { throw FinanceError(message: "Document recognition found inconsistent column counts.") }
            var fields = source.map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            if fields.allSatisfy(\.isEmpty) { continue }
            guard !fields[merchant].isEmpty else { throw FinanceError(message: "A recognized transaction description is empty.") }
            var date: Date?
            for format in ["yyyy-MM-dd", "yyyy/MM/dd", "dd MMM yyyy", "d MMM yyyy", "MMM d, yyyy"] {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = format; formatter.isLenient = false
                if let value = formatter.date(from: fields[dateIndex]), formatter.string(from: value).caseInsensitiveCompare(fields[dateIndex]) == .orderedSame { date = value; break }
            }
            if date == nil, years.count == 1, let year = years.first {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "dd MMM yyyy"; formatter.isLenient = false
                if fields[dateIndex].range(of: #"^\d{1,2} [A-Za-z]{3}$"#, options: .regularExpression) != nil { date = formatter.date(from: fields[dateIndex] + " " + year) }
            }
            guard let date else { throw FinanceError(message: "A recognized date is ambiguous. Use YYYY-MM-DD or a written month in a CSV export.") }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
            fields[dateIndex] = formatter.string(from: date)
            for (i, heading) in headers.enumerated() where heading == "debit" || heading == "credit" {
                if ["-", "–", "—", ""].contains(fields[i]) { fields[i] = "0" }
            }
            output.append(fields)
        }
        func escaped(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let csv = output.map { $0.map(escaped).joined(separator: ",") }.joined(separator: "\n")
        var batch = try TransactionImport.csv(Data(csv.utf8))
        guard batch.currencyCode == nil || currency == nil || batch.currencyCode == currency else { throw FinanceError(message: "Recognized table currency conflicts with the statement.") }
        batch.currencyCode = currency ?? batch.currencyCode
        for i in batch.rows.indices { batch.rows[i].currencyCode = batch.currencyCode }
        try TransactionImport.validate(batch)
        return batch
    }
}
