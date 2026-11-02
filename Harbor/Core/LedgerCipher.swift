import Foundation
import CryptoKit

// Authenticate the format marker as well as the ledger so altered files fail closed.
enum LedgerCipher {
    private static let header = Data("HARBOR-ENC-1\n".utf8)
    static func encrypt(_ bytes: Data, key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(bytes, using: key, authenticating: header)
        guard let combined = sealed.combined else { throw FinanceError(message: "Could not encrypt records.") }
        return header + combined
    }
    static func decrypt(_ bytes: Data, key: SymmetricKey) throws -> Data {
        guard bytes.starts(with: header) else { throw FinanceError(message: "Unsupported encrypted ledger format.") }
        let box = try AES.GCM.SealedBox(combined: Data(bytes.dropFirst(header.count)))
        return try AES.GCM.open(box, using: key, authenticating: header)
    }
}


// Portable backups use an independent random key; the authenticated marker versions the wire format.
enum PortableBackup {
    static let maximumBytes = 25_000_000
    private static let header = Data("HARBOR-BACKUP-1\n".utf8)
    static func recoveryKey() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).map { String(format: "%02X", $0) }.joined() }
    }
    static func key(_ text: String) throws -> SymmetricKey {
        let clean = text.filter { !$0.isWhitespace && $0 != "-" }
        guard clean.count == 64, clean.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw FinanceError(message: "Enter the complete 64-character recovery key.")
        }
        let chars = Array(clean)
        let bytes = stride(from: 0, to: 64, by: 2).compactMap { UInt8(String(chars[$0...($0 + 1)]), radix: 16) }
        return SymmetricKey(data: Data(bytes))
    }
    static func encrypt(_ data: FinanceData, recoveryKey: String) throws -> Data {
        try data.validate()
        let plain = try JSONEncoder().encode(data)
        guard plain.count <= maximumBytes - 128 else { throw FinanceError(message: "Backup is too large.") }
        let box = try AES.GCM.seal(plain, using: key(recoveryKey), authenticating: header)
        guard let combined = box.combined else { throw FinanceError(message: "Could not encrypt backup.") }
        return header + combined
    }
    static func decode(_ bytes: Data, recoveryKey: String = "") throws -> FinanceData {
        guard bytes.count <= maximumBytes else { throw FinanceError(message: "Backup is too large.") }
        let plain: Data
        if bytes.starts(with: Data("HARBOR-".utf8)) {
            guard bytes.starts(with: header) else { throw FinanceError(message: "Unsupported backup version.") }
            do {
                let box = try AES.GCM.SealedBox(combined: Data(bytes.dropFirst(header.count)))
                plain = try AES.GCM.open(box, using: key(recoveryKey), authenticating: header)
            } catch { throw FinanceError(message: "Could not unlock backup. Check its recovery key and file integrity.") }
        } else { plain = bytes }
        let result = try JSONDecoder().decode(FinanceData.self, from: plain)
        try result.validate()
        return result
    }
}
