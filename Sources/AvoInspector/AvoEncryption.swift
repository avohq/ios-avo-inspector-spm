//
//  AvoEncryption.swift
//  AvoInspector
//
//  ECIES encryption (P-256 + AES-256-GCM) for property value encryption.
//  v0x01 wire format: [0x01][65-byte pubkey][12-byte nonce][16-byte tag][ciphertext]
//

import Foundation
import CryptoKit
import Security

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
@objc public class AvoEncryption: NSObject {

    // MARK: - Constants

    private static let kNonceLength = 12
    private static let kAuthTagLength = 16
    private static let kUncompressedKeyLength = 65
    private static let kVersionByte: UInt8 = 0x01

    // MARK: - Public API

    @objc public class func encrypt(_ plaintext: String?,
                                     recipientPublicKeyHex: String?) -> String? {
        guard let plaintext = plaintext,
              let recipientPublicKeyHex = recipientPublicKeyHex,
              !recipientPublicKeyHex.isEmpty else {
            return nil
        }

        do {
            // 1. Parse recipient public key from hex
            guard let pubKeyBytes = hexToBytes(recipientPublicKeyHex),
                  let uncompressedPubKeyData = parseAndUncompressPublicKey(pubKeyBytes) else {
                return nil
            }

            guard let recipientKey = createECPublicKey(from: uncompressedPubKeyData) else {
                return nil
            }

            // 2. Generate ephemeral P-256 keypair
            guard let (ephemeralPrivate, ephemeralPublic) = generateEphemeralKeyPair() else {
                return nil
            }

            // 3. ECDH shared secret
            guard let sharedSecret = computeECDHSharedSecret(
                privateKey: ephemeralPrivate, publicKey: recipientKey) else {
                return nil
            }

            // 4. KDF: SHA-256(sharedSecret) -> 32-byte AES key
            let aesKeyData = SHA256.hash(data: sharedSecret)
            let aesKey = SymmetricKey(data: aesKeyData)

            // 5. Generate random 12-byte nonce
            let nonce = AES.GCM.Nonce()

            // 6. AES-256-GCM encrypt (no AAD)
            guard let plaintextData = plaintext.data(using: .utf8) else {
                return nil
            }
            let sealedBox = try AES.GCM.seal(plaintextData, using: aesKey, nonce: nonce)

            // 7. Export ephemeral public key as uncompressed point
            guard let ephemeralPubData = exportUncompressedPublicKey(ephemeralPublic),
                  ephemeralPubData.count == kUncompressedKeyLength else {
                return nil
            }

            // 8. Assemble v0x01 wire format:
            //    [0x01][65-byte pubkey][12-byte nonce][16-byte tag][ciphertext]
            var output = Data(capacity: 1 + kUncompressedKeyLength + kNonceLength + kAuthTagLength + sealedBox.ciphertext.count)
            output.append(kVersionByte)
            output.append(ephemeralPubData)
            output.append(contentsOf: nonce)          // 12 bytes
            output.append(sealedBox.tag)               // 16 bytes
            output.append(sealedBox.ciphertext)

            // 9. Base64 encode
            return output.base64EncodedString()
        } catch {
            NSLog("[avo] Avo Inspector: Encryption failed: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - Key Parsing

    internal class func hexToBytes(_ hex: String) -> Data? {
        if hex.isEmpty {
            return nil
        }

        var hexStr = hex
        // Remove 0x prefix if present
        if hexStr.hasPrefix("0x") || hexStr.hasPrefix("0X") {
            hexStr = String(hexStr.dropFirst(2))
        }

        if hexStr.count % 2 != 0 {
            return nil
        }

        var data = Data(capacity: hexStr.count / 2)
        var index = hexStr.startIndex
        while index < hexStr.endIndex {
            let nextIndex = hexStr.index(index, offsetBy: 2)
            let byteString = hexStr[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        return data
    }

    internal class func parseAndUncompressPublicKey(_ pubKeyBytes: Data) -> Data? {
        let length = pubKeyBytes.count

        if length == 33 && (pubKeyBytes[0] == 0x02 || pubKeyBytes[0] == 0x03) {
            // Compressed key: prefix (1 byte) + X (32 bytes)
            return decompressPublicKey(pubKeyBytes)
        } else if length == 65 && pubKeyBytes[0] == 0x04 {
            // Uncompressed with 0x04 prefix
            return pubKeyBytes
        } else if length == 64 {
            // Raw X + Y without prefix, add 0x04
            var uncompressed = Data(capacity: 65)
            uncompressed.append(0x04)
            uncompressed.append(pubKeyBytes)
            return uncompressed
        }

        return nil
    }

    internal class func decompressPublicKey(_ compressedKey: Data) -> Data? {
        let yOdd = compressedKey[0] == 0x03

        // Extract X coordinate (32 bytes after prefix)
        let xData = compressedKey.subdata(in: 1..<33)

        guard let yData = computeYFromX(xData, yOdd: yOdd) else {
            return nil
        }

        // Build uncompressed point: 0x04 + X(32) + Y(32)
        var uncompressed = Data(capacity: 65)
        uncompressed.append(0x04)
        uncompressed.append(xData)
        uncompressed.append(yData)
        return uncompressed
    }

    // MARK: - secp256r1 Big Number Arithmetic

    // All numbers are 32-byte big-endian unsigned integers

    // secp256r1 prime p
    private static let secp256r1_p: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    ]

    // secp256r1 a = p - 3
    private static let secp256r1_a: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFC
    ]

    // secp256r1 b
    private static let secp256r1_b: [UInt8] = [
        0x5A, 0xC6, 0x35, 0xD8, 0xAA, 0x3A, 0x93, 0xE7,
        0xB3, 0xEB, 0xBD, 0x55, 0x76, 0x98, 0x86, 0xBC,
        0x65, 0x1D, 0x06, 0xB0, 0xCC, 0x53, 0xB0, 0xF6,
        0x3B, 0xCE, 0x3C, 0x3E, 0x27, 0xD2, 0x60, 0x4B
    ]

    // (p + 1) / 4 -- used for modular square root since p ≡ 3 (mod 4)
    private static let secp256r1_p_plus1_div4: [UInt8] = [
        0x3F, 0xFF, 0xFF, 0xFF, 0xC0, 0x00, 0x00, 0x00,
        0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ]

    // Modular multiplication: (a * b) mod p using 64-byte intermediate
    private class func bigMulMod(_ a: [UInt8], _ b: [UInt8], _ p: [UInt8]) -> [UInt8] {
        // Compute a * b into a 64-byte buffer
        var product = [UInt8](repeating: 0, count: 64)

        for i in stride(from: 31, through: 0, by: -1) {
            var carry: UInt16 = 0
            for j in stride(from: 31, through: 0, by: -1) {
                let val = UInt32(product[i + j + 1]) + UInt32(a[i]) * UInt32(b[j]) + UInt32(carry)
                product[i + j + 1] = UInt8(val & 0xFF)
                carry = UInt16(val >> 8)
            }
            product[i] = product[i] &+ UInt8(carry)
        }

        // Reduce product mod p
        return bigMod(product, p)
    }

    // Modular reduction: num (arbitrary length, big-endian) mod p (32 bytes) -> result (32 bytes)
    // Uses schoolbook byte-by-byte long division with repeated subtraction.
    private class func bigMod(_ num: [UInt8], _ p: [UInt8]) -> [UInt8] {
        // 33-byte accumulator: one extra byte for overflow during shift
        var remainder = [UInt8](repeating: 0, count: 33)

        for i in 0..<num.count {
            // remainder = (remainder << 8) | num[i]
            for j in 0..<32 {
                remainder[j] = remainder[j + 1]
            }
            remainder[32] = num[i]

            // Reduce: while remainder >= p, subtract p
            while bigCompare33(remainder, p) >= 0 {
                bigSub33(&remainder, p)
            }
        }

        // Result is in remainder[1..32]
        return Array(remainder[1...32])
    }

    private class func bigCompare33(_ a: [UInt8], _ p: [UInt8]) -> Int {
        // Compare 33-byte a with 32-byte p (p has implicit leading zero)
        if a[0] != 0 { return 1 } // a has a non-zero 33rd byte, so a > p
        return bigCompare(Array(a[1...32]), p)
    }

    private class func bigSub33(_ a: inout [UInt8], _ p: [UInt8]) {
        // Subtract 32-byte p from 33-byte a, result in a
        var borrow: Int16 = 0
        for i in stride(from: 32, through: 1, by: -1) {
            var diff = Int16(a[i]) - Int16(p[i - 1]) - borrow
            if diff < 0 {
                diff += 256
                borrow = 1
            } else {
                borrow = 0
            }
            a[i] = UInt8(diff)
        }
        a[0] = UInt8(Int16(a[0]) - borrow)
    }

    private class func bigCompare(_ a: [UInt8], _ p: [UInt8]) -> Int {
        // Compare a (same length as p, 32 bytes) with p
        assert(a.count == 32 && p.count == 32)
        for i in 0..<32 {
            if a[i] > p[i] { return 1 }
            if a[i] < p[i] { return -1 }
        }
        return 0
    }

    // Modular addition: (a + b) mod p, all 32 bytes
    private class func bigAddMod(_ a: [UInt8], _ b: [UInt8], _ p: [UInt8]) -> [UInt8] {
        var carry: UInt16 = 0
        var sum = [UInt8](repeating: 0, count: 33)
        for i in stride(from: 31, through: 0, by: -1) {
            let s = UInt16(a[i]) + UInt16(b[i]) + carry
            sum[i + 1] = UInt8(s & 0xFF)
            carry = s >> 8
        }
        sum[0] = UInt8(carry)

        // Reduce mod p
        while bigCompare33(sum, p) >= 0 {
            bigSub33(&sum, p)
        }
        return Array(sum[1...32])
    }

    // Modular exponentiation: base^exp mod p (all 32 bytes)
    private class func bigModPow(_ base: [UInt8], _ exp: [UInt8], _ p: [UInt8]) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: 32)
        r[31] = 1 // r = 1

        var b = base

        // Square-and-multiply from LSB
        for byteIdx in stride(from: 31, through: 0, by: -1) {
            for bitIdx in 0..<8 {
                if (exp[byteIdx] >> bitIdx) & 1 == 1 {
                    r = bigMulMod(r, b, p)
                }
                b = bigMulMod(b, b, p)
            }
        }

        return r
    }

    // Modular subtraction: (p - a) mod p
    private class func bigSubFromP(_ a: [UInt8], _ p: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 32)
        var borrow: Int16 = 0
        for i in stride(from: 31, through: 0, by: -1) {
            var diff = Int16(p[i]) - Int16(a[i]) - borrow
            if diff < 0 {
                diff += 256
                borrow = 1
            } else {
                borrow = 0
            }
            result[i] = UInt8(diff)
        }
        return result
    }

    internal class func computeYFromX(_ xData: Data, yOdd: Bool) -> Data? {
        let x = [UInt8](xData)
        let p = secp256r1_p
        let a = secp256r1_a
        let b = secp256r1_b

        // Compute y^2 = x^3 + a*x + b (mod p)
        // Step 1: x^2 mod p
        let x2 = bigMulMod(x, x, p)

        // Step 2: x^3 mod p
        let x3 = bigMulMod(x2, x, p)

        // Step 3: a*x mod p
        let ax = bigMulMod(a, x, p)

        // Step 4: x^3 + a*x mod p
        let sum1 = bigAddMod(x3, ax, p)

        // Step 5: x^3 + a*x + b mod p
        let ySquared = bigAddMod(sum1, b, p)

        // Step 6: y = ySquared^((p+1)/4) mod p (since p ≡ 3 mod 4)
        let y = bigModPow(ySquared, secp256r1_p_plus1_div4, p)

        // Check parity
        let yIsOdd = (y[31] & 1) != 0
        if yIsOdd != yOdd {
            let negY = bigSubFromP(y, p)
            return Data(negY)
        }

        return Data(y)
    }

    // MARK: - SecKey Operations

    private class func createECPublicKey(from uncompressedData: Data) -> SecKey? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(uncompressedData as CFData,
                                              attributes as CFDictionary, &error) else {
            if let err = error {
                NSLog("[avo] Avo Inspector: Failed to create EC public key: %@", err.takeRetainedValue().localizedDescription)
            }
            return nil
        }
        return key
    }

    private class func generateEphemeralKeyPair() -> (SecKey, SecKey)? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let err = error {
                NSLog("[avo] Avo Inspector: Failed to generate ephemeral keypair: %@", err.takeRetainedValue().localizedDescription)
            }
            return nil
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return nil
        }

        return (privateKey, publicKey)
    }

    private class func computeECDHSharedSecret(privateKey: SecKey, publicKey: SecKey) -> Data? {
        var error: Unmanaged<CFError>?
        guard let sharedSecretRef = SecKeyCopyKeyExchangeResult(
            privateKey,
            .ecdhKeyExchangeStandard,
            publicKey,
            [:] as CFDictionary,
            &error) else {
            if let err = error {
                NSLog("[avo] Avo Inspector: ECDH failed: %@", err.takeRetainedValue().localizedDescription)
            }
            return nil
        }
        return sharedSecretRef as Data
    }

    private class func exportUncompressedPublicKey(_ publicKey: SecKey) -> Data? {
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?,
              keyData.count == kUncompressedKeyLength else {
            if let err = error {
                NSLog("[avo] Avo Inspector: Failed to export public key: %@", err.takeRetainedValue().localizedDescription)
            }
            return nil
        }
        return keyData
    }
}
