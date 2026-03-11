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
        // iOS 16+: CryptoKit can parse compressed keys directly
        if #available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *) {
            guard let publicKey = try? P256.KeyAgreement.PublicKey(
                compressedRepresentation: compressedKey
            ) else {
                return nil
            }
            return publicKey.x963Representation
        }

        // iOS 13-15: Attempt Security framework round-trip.
        // SecKeyCreateWithData may accept compressed EC keys on some OS versions,
        // and SecKeyCopyExternalRepresentation always returns uncompressed form.
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let tempKey = SecKeyCreateWithData(
            compressedKey as CFData,
            attributes as CFDictionary,
            &error
        ) else {
            if AvoInspector.isLogging() {
                NSLog("[avo] Avo Inspector: Compressed public key decompression is not supported on this iOS version (requires iOS 16+). Provide an uncompressed key (65-byte 0x04-prefixed or 64-byte raw X||Y) to support iOS 13-15.")
            }
            return nil
        }
        guard let uncompressed = SecKeyCopyExternalRepresentation(tempKey, &error) as Data?,
              uncompressed.count == kUncompressedKeyLength else {
            if AvoInspector.isLogging() {
                NSLog("[avo] Avo Inspector: Failed to export uncompressed public key on iOS 13-15. Provide an uncompressed key (65-byte 0x04-prefixed or 64-byte raw X||Y) to support iOS 13-15.")
            }
            return nil
        }
        return uncompressed
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
