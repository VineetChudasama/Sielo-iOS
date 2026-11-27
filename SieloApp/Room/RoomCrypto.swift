import Foundation
import CryptoKit

/// Mirrors app/room/crypto/RoomCrypto.kt:
/// AES-256-GCM with 12-byte nonce and wire format "{ivBase64}:{ciphertextPlusTagBase64}".
public enum RoomCrypto {
    public static func generateKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func deriveKey(roomId: String) -> String {
        let input = "\(roomId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()):sielo_e2ee_salt_v3"
        let digest = SHA256.hash(data: Data(input.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func encrypt(plaintext: String, base64Key: String) -> String? {
        guard let keyData = decodeURLSafeBase64(base64Key), keyData.count == 32 else { return nil }
        let key = SymmetricKey(data: keyData)
        do {
            let nonce = AES.GCM.Nonce()
            let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key, nonce: nonce)
            let ivBase64 = Data(nonce).base64EncodedString()
            let combinedCipherTag = sealed.ciphertext + sealed.tag
            let cipherBase64 = combinedCipherTag.base64EncodedString()
            return "\(ivBase64):\(cipherBase64)"
        } catch {
            return nil
        }
    }

    public static func decrypt(payload: String, base64Key: String) -> String? {
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let keyData = decodeURLSafeBase64(base64Key), keyData.count == 32,
              let ivData = Data(base64Encoded: parts[0]),
              let cipherPlusTag = Data(base64Encoded: parts[1]),
              cipherPlusTag.count > 16 else {
            return nil
        }
        let ciphertext = cipherPlusTag.prefix(cipherPlusTag.count - 16)
        let tag = cipherPlusTag.suffix(16)
        do {
            let key = SymmetricKey(data: keyData)
            let nonce = try AES.GCM.Nonce(data: ivData)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let decrypted = try AES.GCM.open(box, using: key)
            return String(data: decrypted, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func decodeURLSafeBase64(_ str: String) -> Data? {
        var b64 = str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 { b64 += String(repeating: "=", count: 4 - rem) }
        return Data(base64Encoded: b64)
    }
}
