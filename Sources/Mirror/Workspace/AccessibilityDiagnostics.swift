import Foundation
import Security

/// Diagnostic history only. It never substitutes for the current macOS permission check.
struct AccessibilityIdentity: Equatable {
    let codeHash: String?
    let adHoc: Bool
    let appURL: URL

    static func current() -> Self {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        var hash: String?
        var adHoc = false
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(
                staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
            let values = information as? [String: Any]
        {
            hash = (values[kSecCodeInfoUnique as String] as? Data)?
                .map { String(format: "%02x", $0) }.joined()
            let flags = (values[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
            adHoc = SecCodeSignatureFlags(rawValue: flags).contains(.adhoc)
        }
        return Self(codeHash: hash, adHoc: adHoc, appURL: Bundle.main.bundleURL)
    }
}

final class AccessibilityDiagnostics {
    enum State: Equatable {
        case granted, notGranted, previouslyGranted, changedDevelopmentBuild
    }

    let identity: AccessibilityIdentity
    private let defaults: UserDefaults
    private let grantedKey = "mirror.accessibility.lastGranted"
    private let hashKey = "mirror.accessibility.lastGrantedCodeHash"

    init(identity: AccessibilityIdentity = .current(), defaults: UserDefaults = .standard) {
        self.identity = identity
        self.defaults = defaults
    }

    func observe(granted: Bool) -> State {
        if granted {
            if !defaults.bool(forKey: grantedKey) { defaults.set(true, forKey: grantedKey) }
            if let hash = identity.codeHash, defaults.string(forKey: hashKey) != hash {
                defaults.set(hash, forKey: hashKey)
            } else if identity.codeHash == nil {
                defaults.removeObject(forKey: hashKey)
            }
            return .granted
        }
        guard defaults.bool(forKey: grantedKey) else { return .notGranted }
        if identity.adHoc, let previous = defaults.string(forKey: hashKey),
            let current = identity.codeHash, previous != current
        {
            return .changedDevelopmentBuild
        }
        return .previouslyGranted
    }
}
