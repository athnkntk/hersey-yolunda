import Foundation

enum InvitationInput {
    static var configuredDomain: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "HYInviteDomain") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    static func link(token: String, domain: String? = configuredDomain) -> URL? {
        guard validToken(token) else { return nil }
        var components = URLComponents()
        if let domain, !domain.isEmpty {
            components.scheme = "https"
            components.host = domain
            components.path = "/invite"
        } else {
            components.scheme = "herseyyolunda"
            components.host = "invite"
        }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    static func credentials(_ raw: String) -> [String: String]? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let token = customSchemeToken(value) { return ["token": token] }
        if let token = httpsInviteToken(value) { return ["token": token] }
        if validToken(value) { return ["token": value] }
        let code = value.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard code.count == 12, code.allSatisfy({ "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) }) else { return nil }
        return ["code": code]
    }

    private static func customSchemeToken(_ raw: String) -> String? {
        guard let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "herseyyolunda",
              components.host == "invite",
              components.path.isEmpty || components.path == "/" else { return nil }
        return soleToken(components)
    }

    private static func httpsInviteToken(_ raw: String) -> String? {
        guard let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              components.path == "/invite" || components.path == "/invite/",
              let host = components.host, host.contains(".") else { return nil }
        return soleToken(components)
    }

    private static func soleToken(_ components: URLComponents) -> String? {
        let tokens = components.queryItems?.filter { $0.name == "token" } ?? []
        guard tokens.count == 1, let token = tokens.first?.value, validToken(token) else { return nil }
        return token
    }

    private static func validToken(_ value: String) -> Bool {
        value.utf8.count == 43 && value.unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value) || (48...57).contains(scalar.value) || scalar.value == 45 || scalar.value == 95
        }
    }
}
