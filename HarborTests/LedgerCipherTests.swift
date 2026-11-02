import XCTest
import CryptoKit
@testable import HarborCore

// Test confidentiality, fresh nonces, and rejection of wrong keys or altered ledger bytes.
final class LedgerCipherTests: XCTestCase {
    func testRoundTripAndRandomizedCiphertext() throws {
        let bytes = try JSONEncoder().encode(FinanceData.demo())
        let key = SymmetricKey(size: .bits256)
        let first = try LedgerCipher.encrypt(bytes, key: key)
        let second = try LedgerCipher.encrypt(bytes, key: key)
        XCTAssertNotEqual(first, second)
        XCTAssertNil(first.range(of: Data("transactions".utf8)))
        XCTAssertEqual(try LedgerCipher.decrypt(first, key: key), bytes)
    }
    func testRejectsWrongKeyTamperingAndTruncation() throws {
        let key = SymmetricKey(size: .bits256)
        let bytes = try LedgerCipher.encrypt(Data("private records".utf8), key: key)
        XCTAssertThrowsError(try LedgerCipher.decrypt(bytes, key: SymmetricKey(size: .bits256)))
        var altered = bytes
        altered[altered.count - 1] ^= 1
        XCTAssertThrowsError(try LedgerCipher.decrypt(altered, key: key))
        altered = bytes; altered[0] ^= 1
        XCTAssertThrowsError(try LedgerCipher.decrypt(altered, key: key))
        XCTAssertThrowsError(try LedgerCipher.decrypt(Data(bytes.dropLast()), key: key))
        XCTAssertThrowsError(try LedgerCipher.decrypt(Data(), key: key))
    }
}
