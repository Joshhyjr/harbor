import SwiftUI
import UniformTypeIdentifiers

@MainActor final class HarborStore: ObservableObject {
    // Cache expensive cleanup validation once per ledger change, never on every Settings render/tap.
    @Published private(set) var categorySimplificationNeeded = false
    @Published private(set) var data = FinanceData(isDemo: false) {
        didSet { categorySimplificationNeeded = data.needsCategorySimplification; refreshBudgets() }
    }
    // Cache one plan per ledger/month change; piggy banks, totals and Settings share these exact limits.
    @Published private(set) var budgetPlan = AutomaticBudgets()
    var monthlyBudget: Int { data.reportingCategories.reduce(0) { $0 + (budgetPlan.limits[$1.id] ?? $1.limit) } }
    func budgetCategory(_ category: Category) -> Category { budgetPlan.resolved(category) }
    func refreshBudgets() { budgetPlan = AutomaticBudgets.calculate(data: data, month: month) }
    @Published var applePayStatus = ""
    @Published var applePayQuarantined: [PendingApplePayCapture] = []
    @Published var applePayPending: [PendingApplePayCapture] = []
    // Preserve the original in-app error while optionally sending a generic, rate-limited alert.
    @Published var error: String? {
        didSet { if error != nil { ReminderNotifications.shared.reportFailure() } }
    }
    @Published var month = Date() { didSet { refreshBudgets() } }
    private let url: URL
    private let legacyURL: URL
    private let keychain: HarborKeychain
    private var loaded = false
    private var drainingApplePayInbox = false
    private var recoveryRequired = false
    var recoveryNeeded: Bool { recoveryRequired }
    // Debug UI runs have their own ledger and Keychain namespace; there is no authentication bypass.
    static var testing: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        return false
        #endif
    }
    static var keychain: HarborKeychain { HarborKeychain(service: testing ? "com.josh.harbor.ui-testing" : "com.josh.harbor.security") }
    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let prefix = Self.testing ? "harbor-ui-testing" : "harbor-v1"
        url = folder.appendingPathComponent(prefix + ".encrypted")
        legacyURL = folder.appendingPathComponent(prefix + ".json")
        keychain = Self.keychain
        #if DEBUG
        if Self.testing && ProcessInfo.processInfo.arguments.contains("-reset-ui-testing") {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: legacyURL)
            UserDefaults.standard.removeObject(forKey: "harbor.ui-testing.appearance")
            // Reset the isolated Shortcut choice so UI tests always begin with an unselected account.
            UserDefaults.standard.removeObject(forKey: ApplePayCaptureService.selectedAccountPreferenceKey)
            // Alert preferences are isolated from real purchases and reset with the test ledger.
            UserDefaults.standard.removeObject(forKey: PurchaseNotifications.preferenceKey)
            UserDefaults.standard.removeObject(forKey: PurchaseNotifications.errorKey)
            ReminderNotifications.resetTestPreferences()
            // Reset only the test preference, without deleting any encryption key.
            try? keychain.write(Data([0]), account: "app-lock")
            // Exercise migration using a legacy ledger confined to the debug test namespace.
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-legacy") {
                var legacy = FinanceData.demo()
                legacy.name = "Migration Test"
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? JSONEncoder().encode(legacy).write(to: legacyURL, options: .atomic)
            }
            // Seed a locked test fixture to verify launch gating without bypassing authentication.
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-locked") {
                try? keychain.write(Data([1]), account: "app-lock")
            }
            // A fictional held purchase exercises restore recovery using only the debug inbox namespace.
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-held-capture") {
                do {
                    let inbox = try ApplePayCaptureService.inbox(prepare: true)
                    try? FileManager.default.removeItem(at: inbox.folder)
                    let capture = try ApplePayCapture(amount: "8.25", merchant: "Restored held purchase", currency: "CAD", accountID: UUID())
                    try inbox.save(capture)
                    try ApplePayInbox.quarantineFiles(in: inbox.folder)
                } catch { self.error = error.localizedDescription }
            }
        }
        #endif
    }
    func load() {
        guard !loaded else { return }
        loaded = true
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let bytes = try LedgerCipher.decrypt(Data(contentsOf: url), key: keychain.key(create: false))
                let next = try JSONDecoder().decode(FinanceData.self, from: bytes)
                try next.validate()
                // Finish cleanup if an earlier migration stopped after committing ciphertext.
                try removeLegacy()
                data = next
            } else if FileManager.default.fileExists(atPath: legacyURL.path) {
                let next = try JSONDecoder().decode(FinanceData.self, from: Data(contentsOf: legacyURL))
                try persist(next)
                data = next
            } else {
                let next = FinanceData.demo()
                try persist(next)
                data = next
            }
            recoveryRequired = false
            // Retire old blanket import flags after unlock using the normal encrypted, atomic save path.
            if !data.isDemo {
                var reviewed = data
                _ = Categorization.clearExistingReviewFlags(in: &reviewed)
                // Existing history receives the same subscription discovery after normal vault unlock.
                try RecurringBills.autoTrack(in: &reviewed)
                if reviewed != data {
                    _ = update { $0 = reviewed }
                }
            }
            drainApplePayInbox()
            #if DEBUG
            appendRequestedOctoberExamples()
            #endif
        } catch {
            // Preserve unreadable ciphertext and legacy files; never substitute demo records on failure.
            self.error = "Could not open saved data. Existing files are preserved. \(error.localizedDescription)"
            data = FinanceData(isDemo: false)
            recoveryRequired = true
            // Invalid/unreadable records must not leave old bill schedules pending.
            ReminderNotifications.shared.refresh(data: FinanceData(), attentionCount: 0)
        }
    }
    #if DEBUG
    // Explicit local development action for user-requested fictional examples. Runs only after normal unlock/load,
    // requires an exact account name, and uses the same duplicate checks and encrypted save path as Files import.
    private func appendRequestedOctoberExamples() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-append-october-examples") else { return }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let receipt = folder.appendingPathComponent("Harbor-October-examples-result.json")
        var result: [String: String] = [:]
        do {
            guard let index = arguments.firstIndex(of: "-example-account"), index + 1 < arguments.count,
                  let account = data.accounts.first(where: { $0.name == arguments[index + 1] }) else {
                throw FinanceError(message: "Choose the exact existing account name. Available accounts: " + data.accounts.map(\.name).joined(separator: ", "))
            }
            let file = folder.appendingPathComponent("Harbor-October-examples.csv")
            let batch = try TransactionImport.csv(Data(contentsOf: file))
            // Restrict the development action to the labelled examples, never arbitrary statement replacement.
            guard batch.rows.count == 16, batch.rows.allSatisfy({ row in
                let date = Calendar.current.dateComponents([.year, .month, .day], from: row.date)
                return date.year == 2026 && date.month == 10 && (1...14).contains(date.day ?? 0) && row.note.hasPrefix("Fictional October example:")
            }) else { throw FinanceError(message: "The October example file is not the expected sample set.") }
            let duplicates = TransactionImport.duplicates(batch.rows, in: data, account: account.id)
            let rows = batch.rows.filter { !duplicates.contains($0.id) }
            if !rows.isEmpty {
                guard update({ try TransactionImport.apply(rows, to: &$0, accountID: account.id, newAccount: nil, removeDemo: false) }) else {
                    throw FinanceError(message: error ?? "Could not save examples.")
                }
            }
            let october = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15))!
            let forecast = SpendingForecast.calculate(data: data, month: october)
            result = ["status": "saved", "added": String(rows.count), "duplicates": String(duplicates.count), "account": account.name,
                      "transactions": String(data.transactions.count), "octoberSpendingCents": String(data.total(.expense, in: october)),
                      "forecastCents": forecast.estimate.map(String.init) ?? "unavailable"]
        } catch {
            self.error = error.localizedDescription
            result = ["status": "error", "message": error.localizedDescription]
        }
        // A local receipt lets development tooling verify the append without exposing the ledger or encryption key.
        try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]).write(to: receipt, options: [.atomic, .completeFileProtection])
    }
    #endif
    // The main-actor store is the sole ledger writer; Shortcuts only writes independent inbox files.
    func drainApplePayInbox() {
        guard loaded, !recoveryRequired, !drainingApplePayInbox else { return }
        drainingApplePayInbox = true
        defer {
            drainingApplePayInbox = false
            if !applePayPending.isEmpty { ReminderNotifications.shared.reportFailure() }
            refreshReminders()
        }
        applePayPending = []
        do {
            guard FileManager.default.fileExists(atPath: ApplePayCaptureService.folder.path) else { return }
            let inbox = try ApplePayCaptureService.inbox()
            var imported = 0
            var alreadyProcessed = 0
            for file in try inbox.files() {
                let result = importApplePayFile(file, inbox: inbox)
                imported += result.imported
                alreadyProcessed += result.processed
            }
            applePayStatus = captureCheckSummary(imported: imported, processed: alreadyProcessed)
        } catch { applePayStatus = "Inbox unavailable: \(error.localizedDescription)"; ReminderNotifications.shared.reportFailure() }
    }
    // A manual check yields between purchases so the progress indicator and navigation can respond.
    // Keep the same import/delete path as automatic draining, and serialize overlapping drain attempts.
    func checkApplePayCaptures() async -> String {
        guard loaded, !recoveryRequired else { return "Unlock Harbor before checking captures." }
        guard !drainingApplePayInbox else { return "A capture check is already running." }
        drainingApplePayInbox = true
        defer {
            drainingApplePayInbox = false
            if !applePayPending.isEmpty { ReminderNotifications.shared.reportFailure() }
            refreshReminders()
        }
        applePayPending = []
        do {
            guard FileManager.default.fileExists(atPath: ApplePayCaptureService.folder.path) else {
                return "Enable capture in step 2 first."
            }
            let inbox = try ApplePayCaptureService.inbox()
            var imported = 0
            var processed = 0
            await Task.yield()
            for file in try inbox.files() {
                // A background lock or cancelled screen must never import into a concealed ledger.
                guard loaded, !recoveryRequired, !Task.isCancelled else { return "Check paused. Unlock Harbor and try again." }
                let result = importApplePayFile(file, inbox: inbox)
                imported += result.imported
                processed += result.processed
                await Task.yield()
            }
            applePayStatus = captureCheckSummary(imported: imported, processed: processed)
        } catch { applePayStatus = "Inbox unavailable: \(error.localizedDescription)"; ReminderNotifications.shared.reportFailure() }
        return applePayStatus
    }
    private func captureCheckSummary(imported: Int, processed: Int) -> String {
        if imported == 0 && processed == 0 && applePayPending.isEmpty { return "No new captures found." }
        return "\(imported) imported · \(processed) already processed · \(applePayPending.count) need attention"
    }
    private func importApplePayFile(_ file: URL, inbox: ApplePayInbox) -> (imported: Int, processed: Int) {
        var capture: ApplePayCapture?
        do {
            let entry = try inbox.read(file)
            capture = entry
            let existed = data.transactions.contains { $0.id == entry.id }
            guard update({ try entry.apply(to: &$0) }) else { throw FinanceError(message: error ?? "Could not save purchase.") }
            // Notify only for a newly committed entry, even if inbox cleanup subsequently fails.
            if !existed {
                Task { await PurchaseNotifications.shared.send(captureID: entry.id, addedToLedger: true) }
            }
            // Delete only after a durable ledger save; stable IDs make a deletion failure safe to retry.
            try FileManager.default.removeItem(at: file)
            return existed ? (0, 1) : (1, 0)
        } catch {
            applePayPending.append(PendingApplePayCapture(url: file, capture: capture, message: error.localizedDescription))
            return (0, 0)
        }
    }
    // Quarantined captures never enter the automatic drain until explicitly released.
    func refreshQuarantined() {
        applePayQuarantined = []
        do {
            guard FileManager.default.fileExists(atPath: ApplePayCaptureService.quarantine.path) else { return }
            let active = try ApplePayCaptureService.inbox()
            let held = ApplePayInbox(folder: ApplePayCaptureService.quarantine, key: active.key)
            for file in try held.files() {
                do { applePayQuarantined.append(PendingApplePayCapture(url: file, capture: try held.read(file), message: "Held after restore")) }
                catch { applePayQuarantined.append(PendingApplePayCapture(url: file, capture: nil, message: "Unreadable held capture")) }
            }
        } catch { applePayStatus = "Could not read held captures: \(error.localizedDescription)" }
    }
    func releaseQuarantined(_ item: PendingApplePayCapture) {
        guard loaded, !recoveryRequired, let capture = item.capture,
              item.url.deletingLastPathComponent() == ApplePayCaptureService.quarantine else { return }
        do {
            // Validate against the restored ledger before moving. A failed save retains the encrypted file.
            var preview = data; try capture.apply(to: &preview)
            try FileManager.default.moveItem(at: item.url, to: ApplePayCaptureService.folder.appendingPathComponent(item.url.lastPathComponent))
            refreshQuarantined(); drainApplePayInbox()
        } catch { self.error = error.localizedDescription }
    }
    func deleteQuarantined(_ item: PendingApplePayCapture) {
        guard loaded, !recoveryRequired, item.url.deletingLastPathComponent() == ApplePayCaptureService.quarantine else { return }
        do { try FileManager.default.removeItem(at: item.url); refreshQuarantined() }
        catch { self.error = error.localizedDescription }
    }
    func reassignApplePay(_ pending: PendingApplePayCapture, account: Account) {
        guard loaded, !recoveryRequired, pending.capture != nil,
              data.accounts.contains(where: { $0 == account }) else { return }
        do {
            let active = try ApplePayCaptureService.inbox()
            let held = pending.url.deletingLastPathComponent() == ApplePayCaptureService.quarantine
            // Reassignment after restore edits the quarantined file without releasing it for import.
            let inbox = held ? ApplePayInbox(folder: ApplePayCaptureService.quarantine, key: active.key) : active
            try inbox.reassign(pending.url, to: account)
            if held { refreshQuarantined() } else { drainApplePayInbox() }
        } catch { self.error = error.localizedDescription }
    }
    func conceal() {
        // Release the ledger from published state while a new authentication is required.
        data = FinanceData(isDemo: false)
        applePayPending = []
        applePayQuarantined = []
        applePayStatus = ""
        loaded = false
        error = nil
    }
    // Reminders are derived only while the real ledger is available, never by unlocking in the background.
    func refreshReminders() {
        guard loaded, !recoveryRequired else { return }
        ReminderNotifications.shared.refresh(data: data, attentionCount: applePayPending.count + applePayQuarantined.count)
    }
    func completeDailyCheckIn(on date: Date = Date()) {
        guard loaded, !recoveryRequired, !data.isDemo else { return }
        var next = data.checkInStreak ?? CheckInStreak()
        let previousBest = next.best
        guard next.complete(on: date) else { return }
        // Progress becomes visible and celebrates only after the encrypted save succeeds.
        if update({ $0.checkInStreak = next }), next.best > previousBest {
            ReminderNotifications.shared.celebrate(days: next.count)
        }
    }
    @discardableResult func update(_ change: (inout FinanceData) throws -> Void) -> Bool {
        guard loaded, !recoveryRequired else { error = "Restore a valid backup in Settings to recover your saved data."; return false }
        do {
            var next = data
            next.version = max(next.version, 2)
            try change(&next)
            // Preserve the schema required by audit history across every ordinary edit.
            next.version = max(next.version, next.requiredVersion)
            // Recheck after category corrections or manual records; explicit bill edits remain authoritative.
            if !next.isDemo { try RecurringBills.autoTrack(in: &next) }
            try persist(next)
            data = next
            refreshReminders()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    // Replace atomically with a valid empty ledger; failure leaves published records intact.
    // Keep the encrypted file so a subsequent launch cannot reseed sample records.
    @discardableResult func clearAllData() -> Bool {
        guard loaded, !recoveryRequired else { error = "Unlock and recover Harbor before resetting."; return false }
        var captureDisabled = false
        do {
            // Disable first: any cleanup failure leaves capture blocked, preventing a later automatic re-import.
            try ApplePayCaptureService.keychain.write(Data([0]), account: "capture-enabled")
            captureDisabled = true
            if FileManager.default.fileExists(atPath: ApplePayCaptureService.folder.path) {
                try FileManager.default.removeItem(at: ApplePayCaptureService.folder)
            }
            try ApplePayCaptureService.keychain.delete("ledger-key")
            try ApplePayCaptureService.keychain.delete("account-options")
            try ApplePayCaptureService.keychain.delete("capture-verified")
            applePayPending = []; applePayQuarantined = []; applePayStatus = "Capture disabled."
        } catch { self.error = "Reset incomplete. \(captureDisabled ? "Capture is disabled." : "Capture could not be disabled.") \(error.localizedDescription)"; return false }
        let saved = update { $0 = FinanceData(name: "You", isDemo: false) }
        if saved {
            month = Date()
            // A cleared ledger no longer owns the previously selected Shortcut account.
            UserDefaults.standard.removeObject(forKey: ApplePayCaptureService.selectedAccountPreferenceKey)
        }
        return saved
    }
    private func removeLegacy() throws {
        if FileManager.default.fileExists(atPath: legacyURL.path) { try FileManager.default.removeItem(at: legacyURL) }
    }
    private func persist(_ next: FinanceData, recovering: Bool = false) throws {
        try next.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let key = try keychain.key(create: recovering || !FileManager.default.fileExists(atPath: url.path))
        let bytes = try LedgerCipher.encrypt(JSONEncoder().encode(next), key: key)
        // Commit authenticated ciphertext atomically before removing any previous plaintext ledger.
        try bytes.write(to: url, options: [.atomic, .completeFileProtection])
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
        try removeLegacy()
    }
    func restore(_ bytes: Data) throws {
        guard loaded else { throw FinanceError(message: "Unlock Harbor before restoring a backup.") }
        guard bytes.count <= 25_000_000 else { throw FinanceError(message: "Backup is too large.") }
        var next = try JSONDecoder().decode(FinanceData.self, from: bytes)
        try next.validate()
        next.version = max(next.version, 2)
        // Quarantine before replacement so pre-restore captures cannot silently enter the restored ledger.
        // A partial move or failed ledger write leaves every file recoverable for explicit review.
        if FileManager.default.fileExists(atPath: ApplePayCaptureService.folder.path) {
            let files = try FileManager.default.contentsOfDirectory(at: ApplePayCaptureService.folder, includingPropertiesForKeys: nil)
            if files.contains(where: { $0.pathExtension == "encrypted" }) { try ApplePayCaptureService.quarantinePending() }
        }
        // Explicitly confirmed restore can provision a key after a device migration or key loss.
        try persist(next, recovering: true)
        data = next
        recoveryRequired = false
        refreshQuarantined()
        refreshReminders()
    }
    // Plain text amounts use the selected report currency unless an account supplies its own currency.
    func format(_ cents: Int, currency: String? = nil) -> String { Money.format(cents, currency: currency ?? data.reportingCurrency) }
    func shiftMonth(_ delta: Int) { month = Calendar.current.date(byAdding: .month, value: delta, to: month) ?? month }
}

// A registered type makes encrypted backups selectable in Files and preserves their extension.
extension UTType {
    static let harborBackup = UTType(exportedAs: "com.josh.harbor.backup", conformingTo: .data)
}
// FileDocument uses the native Files/share sheet, including iCloud Drive when available.
struct HarborDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .harborBackup, .data] }
    var bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}
