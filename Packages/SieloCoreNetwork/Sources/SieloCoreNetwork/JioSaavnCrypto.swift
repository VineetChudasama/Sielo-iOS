import Foundation
import CommonCrypto

/// DES ECB PKCS5 decryption for JioSaavn encrypted media URLs (key = "38346591").
public enum JioSaavnCrypto {
    private static let desKey = "38346591"

    public static func decryptMediaURL(_ encryptedBase64: String) -> String? {
        guard let cipherData = Data(base64Encoded: encryptedBase64),
              let keyData = desKey.data(using: .ascii) else {
            return nil
        }

        let bufferSize = cipherData.count + kCCBlockSizeDES
        var decryptedData = Data(count: bufferSize)
        var numBytesDecrypted: size_t = 0

        let status = decryptedData.withUnsafeMutableBytes { decryptedBytes in
            cipherData.withUnsafeBytes { cipherBytes in
                keyData.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmDES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        kCCKeySizeDES,
                        nil,
                        cipherBytes.baseAddress,
                        cipherData.count,
                        decryptedBytes.baseAddress,
                        bufferSize,
                        &numBytesDecrypted
                    )
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        decryptedData.count = numBytesDecrypted
        return String(data: decryptedData, encoding: .utf8)?
            .replacingOccurrences(of: "http://", with: "https://")
    }
}
