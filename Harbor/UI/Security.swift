import Foundation
import CryptoKit
import Security
import LocalAuthentication
import UIKit

// Keys and the lock preference stay on this device and are unavailable while iOS is locked.
struct HarborKeychain {
    let service: String
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    func read(_ account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = result as? Data else { throw failure(status) }
        return bytes
    }
    func write(_ bytes: Data, account: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: bytes,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var request = query(account)
            attributes.forEach { request[$0.key] = $0.value }
            let added = SecItemAdd(request as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    // Disabling capture removes its separate key; ledger keys are never deleted by this operation.
    func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    func key(create: Bool) throws -> SymmetricKey {
        if let bytes = try read("ledger-key") {
            guard bytes.count == 32 else { throw FinanceError(message: "The saved encryption key is invalid.") }
            return SymmetricKey(data: bytes)
        }
        // Never silently replace a missing key for an existing ciphertext file.
        guard create else { throw FinanceError(message: "The encryption key is missing. Restore a portable backup on this device to recover your records.") }
        let key = SymmetricKey(size: .bits256)
        try write(key.withUnsafeBytes { Data($0) }, account: "ledger-key")
        return key
    }
    private func failure(_ status: OSStatus) -> FinanceError {
        // Unsigned simulator builds lack Keychain entitlements; unlocking cannot repair signing.
        if status == errSecMissingEntitlement {
            return FinanceError(message: "Harbor requires a signed build with Keychain entitlements. Run from Xcode with signing enabled.")
        }
        return FinanceError(message: "Keychain is unavailable (\(status)). Unlock your device and try again.")
    }
}

// LocalAuthentication provides Face ID / Touch ID with the system device-passcode fallback.
@MainActor final class HarborLock: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var unlocked = false
    @Published private(set) var authenticating = false
    @Published var message: String?
    private let keychain: HarborKeychain
    private let privacyShield = HarborPrivacyShield()
    private var context: LAContext?
    private var generation = UUID()
    private var configurationLoaded = false
    init(keychain: HarborKeychain) {
        self.keychain = keychain
        loadConfiguration()
    }
    private func loadConfiguration() {
        do {
            let value = try keychain.read("app-lock")
            guard value == nil || value == Data([0]) || value == Data([1]) else {
                throw FinanceError(message: "The app lock setting could not be read.")
            }
            enabled = value == Data([1])
            unlocked = !enabled
            configurationLoaded = true
            message = nil
        } catch { enabled = true; unlocked = false; message = error.localizedDescription }
    }
    func lock() {
        // Invalidate pending callbacks so a backgrounded authentication cannot unlock the app later.
        generation = UUID()
        context?.invalidate()
        context = nil
        authenticating = false
        if enabled { unlocked = false }
    }
    func unlock() async {
        if !configurationLoaded { loadConfiguration() }
        guard configurationLoaded, !unlocked else { return }
        if await authenticate(reason: "Unlock your Harbor financial records") { unlocked = true }
    }
    func setEnabled(_ value: Bool) async {
        guard value != enabled, await authenticate(reason: value ? "Enable Harbor app lock" : "Turn off Harbor app lock") else { return }
        do {
            try keychain.write(Data([value ? 1 : 0]), account: "app-lock")
            enabled = value
            unlocked = true
        } catch { message = error.localizedDescription }
    }
    private func authenticate(reason: String) async -> Bool {
        guard !authenticating else { return false }
        let request = LAContext()
        var issue: NSError?
        guard request.canEvaluatePolicy(.deviceOwnerAuthentication, error: &issue) else {
            message = issue?.localizedDescription ?? "Set a device passcode in Settings to use app lock."
            return false
        }
        let token = UUID()
        generation = token
        context = request
        authenticating = true
        message = nil
        do {
            let success = try await request.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            guard generation == token else { return false }
            authenticating = false
            context = nil
            return success
        } catch {
            guard generation == token else { return false }
            authenticating = false
            context = nil
            message = error.localizedDescription
            return false
        }
    }
}

// A window-level cover also protects presented editors and the system share/import sheets.
@MainActor final class HarborPrivacyShield: NSObject {
    private var covers: [UIView] = []
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(cover), name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reveal), name: UIScene.didActivateNotification, object: nil)
    }
    @objc private func cover() {
        guard covers.isEmpty else { return }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                let view = UIView(frame: window.bounds)
                view.backgroundColor = .systemBackground
                view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                let label = UILabel()
                label.text = "Harbor • Locked"
                label.font = .preferredFont(forTextStyle: .title1)
                label.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(label)
                NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: view.centerXAnchor), label.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
                window.addSubview(view)
                covers.append(view)
            }
        }
    }
    @objc private func reveal() {
        covers.forEach { $0.removeFromSuperview() }
        covers.removeAll()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}
