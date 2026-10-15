import Foundation
import Security

/// Kullanıcının elinde tuttuğu hesap kurtarma anahtarı: "HYR1." + 32 rastgele
/// baytın kanonik base64url karşılığı (toplam 48 karakter). Sunucu yalnızca
/// HMAC özeti saklar; anahtarın kendisi istemcide üretilir ve asla loglanmaz.
enum RecoveryKey {
    static let prefix = "HYR1."

    static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw LocalError(message: L10n.text("Güvenli kurtarma anahtarı oluşturulamadı."))
        }
        return prefix + canonical(Data(bytes))
    }

    /// Yalnızca dış boşlukları keser; davet kodlarından farklı olarak büyük/küçük
    /// harf duyarlıdır ve içerideki -/_ karakterleri korunur.
    static func normalized(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValid(trimmed) ? trimmed : nil
    }

    static func isValid(_ value: String) -> Bool {
        guard value.hasPrefix(prefix) else { return false }
        let encoded = String(value.dropFirst(prefix.count))
        guard encoded.utf8.count == 43 else { return false }
        var standard = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while standard.count % 4 != 0 { standard += "=" }
        guard let data = Data(base64Encoded: standard), data.count == 32 else { return false }
        return canonical(data) == encoded
    }

    private static func canonical(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
