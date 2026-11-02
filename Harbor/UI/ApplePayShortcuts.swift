import SwiftUI
import AppIntents
import UserNotifications

// Local alerts never include financial details or change whether a purchase is saved.
@MainActor final class PurchaseNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PurchaseNotifications()
    static var preferenceKey: String {
        HarborStore.testing ? "harbor.ui-testing.purchase-alerts" : "harbor.purchase-alerts"
    }
    static var errorKey: String { preferenceKey + ".error" }
    private let center = UNUserNotificationCenter.current()

    func configure() { center.delegate = self }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func settingsDescription() async -> String {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return "Enable purchase alerts to allow notifications."
        case .denied: return "Notifications are blocked. Allow them in iPhone Settings."
        default:
            return settings.alertSetting == .enabled
                ? "Notifications allowed. Delivery follows your iPhone’s Focus and notification settings."
                : "Notification banners are off. Review your iPhone notification settings."
        }
    }

    func send(captureID: UUID, addedToLedger: Bool) async {
        // Automated UI runs must not deliver fixture purchases to the device notification center.
        guard !HarborStore.testing, UserDefaults.standard.bool(forKey: Self.preferenceKey) else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        // Recheck after the await so switching alerts off also cancels work awaiting authorization status.
        guard UserDefaults.standard.bool(forKey: Self.preferenceKey) else { return }
        let content = UNMutableNotificationContent()
        content.title = addedToLedger ? "Transaction added" : "Purchase captured"
        content.body = addedToLedger
            ? "An Apple Pay purchase was added to your Harbor transactions."
            : "Your purchase is saved securely. Unlock Harbor to add it to your transactions."
        content.sound = .default
        content.threadIdentifier = "harbor.apple-pay"
        // Stable identifiers keep repeated scheduling of the same stage from creating extra alerts.
        let identifier = "harbor.purchase.\(captureID.uuidString).\(addedToLedger ? "added" : "captured")"
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            UserDefaults.standard.removeObject(forKey: Self.errorKey)
        } catch {
            // A notification failure must never turn a durable purchase into a failed Shortcut retry.
            UserDefaults.standard.set("A purchase alert could not be delivered. Your saved purchase is unaffected.", forKey: Self.errorKey)
        }
    }

    // Ledger additions normally happen in the foreground, where banners need explicit presentation.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

// Share the same opt-in preference between the bell inbox and Apple Pay setup.
struct PurchaseNotificationSection: View {
    @AppStorage(PurchaseNotifications.preferenceKey) private var enabled = false
    @AppStorage(PurchaseNotifications.errorKey) private var deliveryError = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var permissionStatus = ""
    @State private var requesting = false
    @State private var permissionError = ""

    var body: some View {
        Section("Purchase notifications") {
            Toggle("Apple Pay purchase alerts", isOn: Binding(get: { enabled }, set: { value in
                if !value { enabled = false; return }
                requesting = true
                Task { @MainActor in
                    defer { requesting = false }
                    do {
                        enabled = try await PurchaseNotifications.shared.requestPermission()
                        permissionError = ""
                    } catch {
                        enabled = false
                        permissionError = "Could not request notification permission. Try again."
                    }
                    permissionStatus = await PurchaseNotifications.shared.settingsDescription()
                }
            }))
            .disabled(requesting).accessibilityIdentifier("notifications.purchaseAlerts")
            Text("Get an alert when a purchase is captured, then when it joins your transactions after you unlock Harbor. Merchant names and amounts stay hidden.").font(.caption)
            Text(permissionStatus).font(.caption).accessibilityIdentifier("notifications.permissionStatus")
            if !permissionError.isEmpty { Text(permissionError).font(.caption) }
            if !deliveryError.isEmpty { Text(deliveryError).font(.caption) }
            Button("Open iPhone notification settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
        }
        .task { permissionStatus = await PurchaseNotifications.shared.settingsDescription() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { permissionStatus = await PurchaseNotifications.shared.settingsDescription() } }
        }
    }
}

// This service never opens the ledger. Provision the separate key only from unlocked Settings.
@MainActor enum ApplePayCaptureService {
    // Keep the setup choice on this device; UI tests must never change the user's preference.
    static var selectedAccountPreferenceKey: String {
        HarborStore.testing ? "harbor.ui-testing.apple-pay-account" : "harbor.apple-pay-account"
    }
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(HarborStore.testing ? "apple-pay-testing-inbox" : "apple-pay-inbox")
    }
    static var keychain: HarborKeychain {
        HarborKeychain(service: HarborStore.testing ? "com.josh.harbor.apple-pay-testing" : "com.josh.harbor.apple-pay")
    }
    static var quarantine: URL { folder.appendingPathComponent("quarantine", isDirectory: true) }
    static func quarantinePending() throws {
        // Moving files within the inbox preserves their encryption and requires explicit review after restore.
        try ApplePayInbox.quarantineFiles(in: folder)
    }
    static func inbox(prepare: Bool = false) throws -> ApplePayInbox {
        if prepare { try keychain.write(Data([1]), account: "capture-enabled") }
        guard try keychain.read("capture-enabled") != Data([0]) else {
            throw FinanceError(message: "Apple Pay capture is disabled. Enable the inbox in Harbor Settings.")
        }
        return try ApplePayInbox(folder: folder, key: keychain.key(create: prepare))
    }
}

// Account metadata is cached separately only with setup consent; it contains no balances or transactions.
struct CaptureAccountEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Harbor account"
    static var defaultQuery = CaptureAccountQuery()
    var id: String
    var name: String
    var currency: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(currency)") }
}
struct CaptureAccountMetadata: Codable { var id: String; var name: String; var currency: String }
struct CaptureAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CaptureAccountEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [CaptureAccountEntity] {
        try await MainActor.run {
            guard let bytes = try ApplePayCaptureService.keychain.read("account-options") else { return [] }
            return try JSONDecoder().decode([CaptureAccountMetadata].self, from: bytes).map {
                CaptureAccountEntity(id: $0.id, name: $0.name, currency: $0.currency)
            }
        }
    }
}

struct CaptureApplePayPurchase: AppIntent {
    static var title: LocalizedStringResource = "Capture Apple Pay purchase"
    static var description = IntentDescription("Save an encrypted purchase for import when you next unlock Harbor. Set up the inbox in Harbor Settings first.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static var openAppWhenRun = false
    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "Merchant") var merchant: String
    // Retain the legacy parameter so previously configured automations still run.
    @Parameter(title: "Account ID") var account: String?
    @Parameter(title: "Harbor account") var destinationAccount: CaptureAccountEntity?
    @Parameter(title: "Currency", default: "CAD") var currency: String
    @Parameter(title: "Purchase date") var date: Date?

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        // Report action failures separately from durable-capture and ledger-addition confirmations.
        do {
            guard UIApplication.shared.isProtectedDataAvailable else { throw FinanceError(message: "Unlock your iPhone before capturing a purchase. Run the Shortcut again after unlocking.") }
            guard let accountID = UUID(uuidString: (destinationAccount?.id ?? account ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) else { throw FinanceError(message: "Choose a Harbor account, or use the legacy Account ID from Harbor Settings → Apple Pay Shortcuts.") }
            guard amount.isFinite else { throw FinanceError(message: "The purchase amount is invalid.") }
            // Decimal parsing rejects fractional cents instead of silently rounding financial input.
            let capture = try ApplePayCapture(amount: String(amount), merchant: merchant, date: date ?? Date(), currency: destinationAccount?.currency ?? currency, accountID: accountID)
            do {
                try ApplePayCaptureService.inbox().save(capture)
            }
            catch { throw FinanceError(message: "Could not capture purchase. Unlock your iPhone and enable the inbox in Harbor Settings. \(error.localizedDescription)") }
            // Confirm encrypted custody only after save; this is distinct from a committed ledger entry.
            await PurchaseNotifications.shared.send(captureID: capture.id, addedToLedger: false)
            // Capture is already durable: a status-write failure must not invite a duplicate purchase retry.
            do { try ApplePayCaptureService.keychain.write(Data([1]), account: "capture-verified") }
            catch { return .result(dialog: "Purchase captured. Setup verification status could not be saved; check the inbox in Harbor.") }
            return .result(dialog: "Captured; will import when Harbor is unlocked")
        } catch {
            ReminderNotifications.shared.reportFailure()
            throw error
        }
    }
}

struct ApplePayShortcutsScreen: View {
    @EnvironmentObject var store: HarborStore
    @State private var status = ""
    @State private var inboxReady = false
    @State private var verified = false
    @State private var checkingCapture = false
    @State private var refreshingAccounts = false
    @State private var captureResult = ""
    @State private var accountRefreshResult = ""
    @AppStorage(ApplePayCaptureService.selectedAccountPreferenceKey) private var savedAccountID = ""
    // Resolve against the current ledger so removed or restored-away accounts cannot stay selected.
    private var selectedAccount: UUID? {
        store.data.accounts.first { $0.id.uuidString == savedAccountID }?.id
    }
    var body: some View {
        List {
            // Describe the actual capture source before setup; Harbor does not read Wallet history.
            Section("Shortcut capture") {
                Text("A Shortcut sends purchase details to Harbor. It does not connect your bank or give Harbor direct access to Wallet transactions.")
                    .font(.subheadline).accessibilityIdentifier("shortcuts.captureDescription")
                LearnMoreLink(title: "Shortcut capture", paragraphs: [
                    "Create a personal transaction automation in Apple Shortcuts on your iPhone. The automation supplies the amount and merchant to Harbor’s Capture Apple Pay purchase action.",
                    "Harbor saves an encrypted capture first, then imports it when you unlock the app. This is separate from adding an account or importing a bank statement.",
                    "Capture requires device authentication. Missed or failed automation runs cannot be recovered automatically. A successful test verifies delivery, not every future Wallet trigger or online Apple Pay purchase."
                ])
            }
            Section("1. Choose a Harbor account") {
                Picker("Harbor account", selection: Binding(
                    get: { selectedAccount },
                    set: { savedAccountID = $0?.uuidString ?? "" }
                )) {
                    Text("Choose an account").tag(nil as UUID?)
                    ForEach(store.data.accounts) { Text("\($0.name) · \($0.currency)").tag(Optional($0.id)) }
                }
                .accessibilityIdentifier("shortcuts.account")
                // Expose the saved selection as the picker value for VoiceOver and native UI checks.
                .accessibilityValue(store.data.accounts.first { $0.id == selectedAccount }
                    .map { "\($0.name) · \($0.currency)" } ?? "Choose an account")
                Text("Your account choice is saved on this device.").font(.caption)
                Text("Shortcuts can see account names and currencies, never balances.").font(.caption)
                LearnMoreLink(title: "Account sharing", paragraphs: ["Enabling capture makes account names and currencies available to Harbor’s Shortcuts action on this device. No balances are shared."])
            }
            Section("2. Enable capture on this device") {
                if inboxReady {
                    Label("Encrypted capture inbox enabled", systemImage: "checkmark.shield.fill")
                    Text("Capture stays enabled after closing Harbor.").font(.caption)
                } else {
                    Button("Enable encrypted capture inbox") {
                        do {
                            let options = store.data.accounts.map { CaptureAccountMetadata(id: $0.id.uuidString, name: $0.name, currency: $0.currency) }
                            try ApplePayCaptureService.keychain.write(JSONEncoder().encode(options), account: "account-options")
                            _ = try ApplePayCaptureService.inbox(prepare: true)
                            refreshInboxStatus()
                        } catch { status = error.localizedDescription }
                    }.disabled(selectedAccount == nil)
                }
                if !status.isEmpty { Text(status).font(.caption) }
            }
            PurchaseNotificationSection()
            Section("3. Configure Wallet in Shortcuts") {
                Text("1. Open Shortcuts → Automation → + → Transaction / Wallet.")
                Text("2. Select your card and choose Run Immediately.")
                Text("3. Add Capture Apple Pay purchase. Map Amount and Merchant from Shortcut Input.")
                Text("4. Choose the same named Harbor account. Leave Purchase date blank to use capture time. Repeat for each card.")
                Text("Set this up on your iPhone. Missed captures are not recovered automatically.").font(.caption)
                LearnMoreLink(title: "Automation limits", paragraphs: ["You must create the automation on your iPhone. Capture requires device authentication; failed or missed runs cannot be recovered automatically. This tracks supported card taps, not bank history or guaranteed online Apple Pay purchases."])
            }
            Section("4. Verify capture") {
                Label(verified ? "Capture received on this device" : "No capture verified yet", systemImage: verified ? "checkmark.seal.fill" : "questionmark.circle")
                Text("Run a small “Test capture” purchase in Shortcuts, then return here. Delete the test transaction afterward.").font(.caption)
                LearnMoreLink(title: "Testing capture", paragraphs: ["Run the configured action in Shortcuts with a small test amount and merchant named Test capture, then return here. This creates a real ledger entry: delete the test entry afterward. Receiving a capture verifies delivery, not every future Wallet trigger."])
                verificationActions
            }
            Section("Existing shortcuts") {
                DisclosureGroup("Legacy Account IDs") {
                    if store.data.accounts.isEmpty { Text("Add your own account in Settings first.") }
                    ForEach(store.data.accounts) { account in
                        VStack(alignment: .leading) {
                            Text("\(account.name) · \(account.currency)")
                            Text(account.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                            Button("Copy Account ID") { UIPasteboard.general.string = account.id.uuidString }
                        }
                    }
                }
            }
            heldCaptures
            Section("Inbox") {
                LearnMoreLink(title: "Pending purchases", paragraphs: ["Pending purchases are retained until they can be saved. Statement merchant names, posting dates, and final amounts can differ; review these before importing a statement."])
                Button("Import pending purchases") { store.drainApplePayInbox() }
                if !store.applePayStatus.isEmpty { Text(store.applePayStatus) }
                ForEach(store.applePayPending) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.message).font(.caption)
                        if let capture = item.capture {
                            Text("\(capture.merchant) · \(Money.format(capture.amount, currency: capture.currency))")
                            Menu("Change destination account") {
                                ForEach(store.data.accounts.filter { $0.currency == capture.currency }) { account in
                                    Button("\(account.name) · \(account.currency)") { store.reassignApplePay(item, account: account) }
                                }
                            }
                        }
                        Text("Kept until saved. Check for duplicates when importing statements.").font(.caption)
                    }
                }
            }
        }.navigationTitle("Apple Pay Shortcuts")
            .onAppear { clearUnavailableAccount(); refreshInboxStatus(readHeldCaptures: true) }
            .onChange(of: store.data.accounts.map(\.id)) { _, _ in clearUnavailableAccount() }
    }
    // Results belong beside the tapped action, not in an earlier, offscreen setup section.
    @ViewBuilder private var verificationActions: some View {
        Button {
            guard !checkingCapture, !refreshingAccounts else { return }
            checkingCapture = true
            captureResult = "Checking for captures…"
            Task { @MainActor in
                captureResult = await store.checkApplePayCaptures()
                refreshInboxStatus()
                checkingCapture = false
            }
        } label: {
            HStack { Text(checkingCapture ? "Checking for captures…" : "Check for received capture"); Spacer(); if checkingCapture { ProgressView() } }
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.borderless).disabled(checkingCapture || refreshingAccounts || store.recoveryNeeded)
            .accessibilityIdentifier("shortcuts.checkCapture")
        if !captureResult.isEmpty { Text(captureResult).font(.subheadline).accessibilityIdentifier("shortcuts.checkResult") }
        Button {
            guard !checkingCapture, !refreshingAccounts else { return }
            refreshingAccounts = true
            accountRefreshResult = "Refreshing account choices…"
            Task { @MainActor in
                // Let the pending state render before the single serialized Keychain write.
                await Task.yield()
                do {
                    guard !store.recoveryNeeded, !store.data.accounts.isEmpty else { throw FinanceError(message: "Unlock Harbor and add an account first.") }
                    let options = store.data.accounts.map { CaptureAccountMetadata(id: $0.id.uuidString, name: $0.name, currency: $0.currency) }
                    try ApplePayCaptureService.keychain.write(JSONEncoder().encode(options), account: "account-options")
                    accountRefreshResult = "Account choices refreshed (\(options.count))."
                } catch { accountRefreshResult = "Could not refresh accounts: \(error.localizedDescription)" }
                refreshingAccounts = false
            }
        } label: {
            HStack { Text(refreshingAccounts ? "Refreshing accounts…" : "Refresh account choices in Shortcuts"); Spacer(); if refreshingAccounts { ProgressView() } }
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.borderless).disabled(!inboxReady || checkingCapture || refreshingAccounts || store.recoveryNeeded)
            .accessibilityIdentifier("shortcuts.refreshAccounts")
        if !accountRefreshResult.isEmpty { Text(accountRefreshResult).font(.subheadline).accessibilityIdentifier("shortcuts.refreshResult") }
        if !inboxReady { Text("Enable capture in step 2 to refresh account choices.").font(.caption).foregroundStyle(.secondary) }
    }
    // Keep the restore-recovery section separate so SwiftUI can type-check the setup screen incrementally.
    @ViewBuilder private var heldCaptures: some View {
        if !store.applePayQuarantined.isEmpty {
            Section("Captures held after restore") {
                Text("Older pending captures are quarantined after restoring a backup. Review them individually before importing into the restored ledger.").font(.caption)
                ForEach(store.applePayQuarantined) { item in
                    VStack(alignment: .leading) {
                        Text(item.capture.map { "\($0.merchant) · \(store.format($0.amount, currency: $0.currency))" } ?? item.message)
                        if let capture = item.capture {
                            Text("Destination: \(store.data.accounts.first { $0.id == capture.accountID }?.name ?? "Account unavailable")").font(.caption)
                            // Restored ledgers can have different accounts; correction never releases a held purchase.
                            Menu("Change destination account") {
                                ForEach(store.data.accounts.filter { $0.currency == capture.currency }) { account in
                                    Button("\(account.name) · \(account.currency)") { store.reassignApplePay(item, account: account) }
                                }
                            }
                            Text("Held until you release it for import.").font(.caption)
                            Button("Release this capture for import") { store.releaseQuarantined(item) }
                        }
                        Button("Delete held capture", role: .destructive) { store.deleteQuarantined(item) }
                    // Each recovery action must be independent; List's automatic style can fire both.
                    }.buttonStyle(.borderless)
                }
            }
        }
    }
    private func clearUnavailableAccount() {
        // Require a fresh choice after account deletion or replacement instead of choosing another account.
        if selectedAccount == nil { savedAccountID = "" }
    }
    private func refreshInboxStatus(readHeldCaptures: Bool = false) {
        // Derive readiness from the durable key, not transient view state or a separate preference.
        // Read without provisioning so visiting Settings never silently enables capture.
        do {
            _ = try ApplePayCaptureService.inbox()
            verified = try ApplePayCaptureService.keychain.read("capture-verified") == Data([1])
            if readHeldCaptures { store.refreshQuarantined() }
            inboxReady = true
            status = "Inbox ready. Configure your Wallet automation below."
        } catch {
            inboxReady = false
            verified = false
            status = FileManager.default.fileExists(atPath: ApplePayCaptureService.folder.path)
                ? "Capture inbox unavailable. Existing files are retained. \(error.localizedDescription)"
                : "Choose your account, then enable encrypted capture to begin."
        }
    }
}

// Keep unreadable files visible without exposing ciphertext or dropping purchases.
struct PendingApplePayCapture: Identifiable {
    let url: URL
    let capture: ApplePayCapture?
    let message: String
    var id: URL { url }
}
