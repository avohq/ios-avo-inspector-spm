import XCTest
import CryptoKit
import Security
@testable import AvoInspector

// MARK: - Test Helpers

private func generateTestPrivateKey() -> SecKey? {
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
    ]
    var error: Unmanaged<CFError>?
    return SecKeyCreateRandomKey(attributes as CFDictionary, &error)
}

private func publicKeyHexFromPrivateKey(_ privateKey: SecKey) -> String? {
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else { return nil }
    var error: Unmanaged<CFError>?
    guard let pubData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else { return nil }
    return pubData.map { String(format: "%02x", $0) }.joined()
}

/// Decrypt a v0x01 ECIES ciphertext (base64) using the given private key.
/// Wire format: [0x01][65-byte pubkey][12-byte nonce][16-byte tag][ciphertext]
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
private func decrypt(_ base64: String, privateKey: SecKey) -> String? {
    guard let data = Data(base64Encoded: base64), data.count >= 95 else { return nil }
    guard data[0] == 0x01 else { return nil }

    let ephemeralPubData = data[1..<66]
    let nonceData = data[66..<78]
    let tagData = data[78..<94]
    let ciphertext = data[94...]

    // Reconstruct ephemeral public key
    let keyAttrs: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        kSecAttrKeySizeInBits as String: 256,
    ]
    var error: Unmanaged<CFError>?
    guard let ephemeralPubKey = SecKeyCreateWithData(
        Data(ephemeralPubData) as CFData, keyAttrs as CFDictionary, &error) else { return nil }

    // ECDH shared secret
    guard let sharedSecretRef = SecKeyCopyKeyExchangeResult(
        privateKey, .ecdhKeyExchangeStandard, ephemeralPubKey,
        [:] as CFDictionary, &error) else { return nil }
    let sharedSecret = sharedSecretRef as Data

    // KDF: SHA-256
    let hash = SHA256.hash(data: sharedSecret)
    let aesKey = SymmetricKey(data: hash)

    // AES-256-GCM decrypt
    do {
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tagData)
        let plainData = try AES.GCM.open(sealedBox, using: aesKey)
        return String(data: plainData, encoding: .utf8)
    } catch { return nil }
}

// MARK: - AvoEncryptionTests

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
final class AvoEncryptionTests: XCTestCase {

    private var testPrivateKey: SecKey!
    private var testPublicKeyHex: String!

    override func setUp() {
        super.setUp()
        testPrivateKey = generateTestPrivateKey()
        XCTAssertNotNil(testPrivateKey)
        testPublicKeyHex = publicKeyHexFromPrivateKey(testPrivateKey)
        XCTAssertNotNil(testPublicKeyHex)
    }

    // MARK: - Round-trip Tests

    func test_encryptsAndDecryptsStringValue() {
        let plaintext = "\"hello world\""
        let encrypted = AvoEncryption.encrypt(plaintext, recipientPublicKeyHex: testPublicKeyHex)
        XCTAssertNotNil(encrypted)

        let decrypted = decrypt(encrypted!, privateKey: testPrivateKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    func test_encryptsAndDecryptsHello() {
        let plaintext = "hello"
        let encrypted = AvoEncryption.encrypt(plaintext, recipientPublicKeyHex: testPublicKeyHex)
        XCTAssertNotNil(encrypted)

        let decrypted = decrypt(encrypted!, privateKey: testPrivateKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    func test_encryptsAndDecryptsIntegerValue() {
        let plaintext = "12345"
        let encrypted = AvoEncryption.encrypt(plaintext, recipientPublicKeyHex: testPublicKeyHex)
        XCTAssertNotNil(encrypted)

        let decrypted = decrypt(encrypted!, privateKey: testPrivateKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    func test_encryptsAndDecryptsDoubleValue() {
        let plaintext = "3.14"
        let encrypted = AvoEncryption.encrypt(plaintext, recipientPublicKeyHex: testPublicKeyHex)
        XCTAssertNotNil(encrypted)

        let decrypted = decrypt(encrypted!, privateKey: testPrivateKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    func test_encryptsAndDecryptsBooleanValue() {
        let plaintext = "true"
        let encrypted = AvoEncryption.encrypt(plaintext, recipientPublicKeyHex: testPublicKeyHex)
        XCTAssertNotNil(encrypted)

        let decrypted = decrypt(encrypted!, privateKey: testPrivateKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - Wire Format Tests

    func test_outputFormatHasCorrectStructure() {
        let encrypted = AvoEncryption.encrypt("test", recipientPublicKeyHex: testPublicKeyHex)
        XCTAssertNotNil(encrypted)

        let data = Data(base64Encoded: encrypted!)
        XCTAssertNotNil(data)

        // Minimum size: 1 (version) + 65 (pubkey) + 12 (nonce) + 16 (tag) + at least 1 byte ciphertext = 95
        XCTAssertGreaterThanOrEqual(data!.count, 95)

        // Version byte 0x01
        XCTAssertEqual(data![0], 0x01)
        // Ephemeral public key starts with 0x04 (uncompressed)
        XCTAssertEqual(data![1], 0x04)
    }

    func test_wireFormatOffsets() {
        let encrypted = AvoEncryption.encrypt("test", recipientPublicKeyHex: testPublicKeyHex)
        XCTAssertNotNil(encrypted)

        let data = Data(base64Encoded: encrypted!)!

        // Version byte at offset 0
        XCTAssertEqual(data[0], 0x01)

        // Public key at [1, 66) = 65 bytes, starts with 0x04
        XCTAssertEqual(data[1], 0x04)
        let pubKeyData = data[1..<66]
        XCTAssertEqual(pubKeyData.count, 65)

        // Nonce at [66, 78) = 12 bytes
        let nonceData = data[66..<78]
        XCTAssertEqual(nonceData.count, 12)

        // Auth tag at [78, 94) = 16 bytes
        let tagData = data[78..<94]
        XCTAssertEqual(tagData.count, 16)

        // Ciphertext at [94, ...)
        let ciphertext = data[94...]
        XCTAssertGreaterThan(ciphertext.count, 0)
    }

    func test_differentEncryptionsProduceDifferentOutput() {
        let plaintext = "\"same text\""
        let encrypted1 = AvoEncryption.encrypt(plaintext, recipientPublicKeyHex: testPublicKeyHex)
        let encrypted2 = AvoEncryption.encrypt(plaintext, recipientPublicKeyHex: testPublicKeyHex)

        XCTAssertNotNil(encrypted1)
        XCTAssertNotNil(encrypted2)
        XCTAssertNotEqual(encrypted1, encrypted2)

        // Both should decrypt to the same plaintext
        let decrypted1 = decrypt(encrypted1!, privateKey: testPrivateKey)
        let decrypted2 = decrypt(encrypted2!, privateKey: testPrivateKey)
        XCTAssertEqual(decrypted1, plaintext)
        XCTAssertEqual(decrypted2, plaintext)
    }

    // MARK: - Nil / Empty Input Tests

    func test_returnsNilForNilKey() {
        let result = AvoEncryption.encrypt("test", recipientPublicKeyHex: nil)
        XCTAssertNil(result)
    }

    func test_returnsNilForEmptyKey() {
        let result = AvoEncryption.encrypt("test", recipientPublicKeyHex: "")
        XCTAssertNil(result)
    }

    func test_returnsNilForNilPlaintext() {
        let result = AvoEncryption.encrypt(nil, recipientPublicKeyHex: testPublicKeyHex)
        XCTAssertNil(result)
    }

    func test_returnsNilForInvalidKey() {
        let result = AvoEncryption.encrypt("test", recipientPublicKeyHex: "deadbeef")
        XCTAssertNil(result)
    }

    // MARK: - Compressed Key Decompression Tests

    func test_decompressesKnownSecp256r1TestVector() {
        // secp256r1 generator point G (a known point on the curve)
        // X = 6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296
        // Y = 4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5
        // Y is odd (last byte 0xF5, bit 0 = 1) -> compressed prefix 0x03
        let compressedHex = "036B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296"

        // Encrypt with the compressed generator point. If decompression is wrong,
        // SecKeyCreateWithData will reject the reconstructed uncompressed key -> nil.
        let encrypted = AvoEncryption.encrypt("test", recipientPublicKeyHex: compressedHex)
        XCTAssertNotNil(encrypted)

        // Verify the ephemeral key in the output uses the correct uncompressed format
        let data = Data(base64Encoded: encrypted!)!
        XCTAssertEqual(data[0], 0x01) // version
        XCTAssertEqual(data[1], 0x04) // uncompressed ephemeral key
    }

    func test_compressedKeyDecompressionRoundTrip() {
        // Build compressed key from the test public key
        guard let publicKey = SecKeyCopyPublicKey(testPrivateKey) else {
            XCTFail("Failed to get public key")
            return
        }
        var error: Unmanaged<CFError>?
        guard let pubData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            XCTFail("Failed to export public key")
            return
        }

        // pubData is 0x04 + X(32) + Y(32) = 65 bytes uncompressed
        XCTAssertEqual(pubData.count, 65)
        XCTAssertEqual(pubData[0], 0x04)

        // Compress: prefix based on Y parity + X coordinate
        let prefix: UInt8 = (pubData[64] & 1) != 0 ? 0x03 : 0x02
        var compressedHex = String(format: "%02x", prefix)
        for i in 1...32 {
            compressedHex += String(format: "%02x", pubData[i])
        }
        XCTAssertEqual(compressedHex.count, 66) // 33 bytes * 2 hex chars

        // Encrypt with compressed key
        let plaintext = "\"compressed key test\""
        let encrypted = AvoEncryption.encrypt(plaintext, recipientPublicKeyHex: compressedHex)
        XCTAssertNotNil(encrypted)

        // Decrypt with original private key to verify decompression worked
        let decrypted = decrypt(encrypted!, privateKey: testPrivateKey)
        XCTAssertEqual(decrypted, plaintext)
    }
}
