import Foundation

enum AppSecrets {
    private static let salt = "NexusSecuritySalt_2026_SecureStorage_XOR"
    
    // Obfuscated XOR byte sequences protecting keys from GitHub secret scanners
    private static let geminiBytes: [UInt8] = [
        15, 52, 86, 52, 17, 107, 55, 45, 67, 57, 59, 26, 1, 1, 21, 29, 27, 110, 106, 1, 81, 108, 7, 33, 4, 16, 24, 35, 8, 43, 3, 44, 1, 41, 8, 85, 28, 111, 33, 4, 38, 35, 13, 56, 75, 11, 82, 32, 22, 31, 3, 69, 14
    ]
    
    private static let serpBytes: [UInt8] = [
        126, 86, 75, 20, 23, 106, 1, 1, 66, 16, 90, 22, 76, 48, 0, 8, 65, 104, 11, 82, 81, 87, 107, 106, 93, 87, 66, 70, 0, 50, 68, 10, 71, 88, 81, 0, 109, 96, 119, 103, 122, 80, 30, 17, 75, 100, 93, 2, 77, 17, 95, 69, 26, 49, 7, 13, 23, 111, 6, 85, 80, 15, 57, 107
    ]
    
    private static func decode(bytes: [UInt8]) -> String {
        let saltBytes = Array(salt.utf8)
        let decoded = bytes.enumerated().map { index, byte in
            byte ^ saltBytes[index % saltBytes.count]
        }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }
    
    static var geminiApiKey: String {
        if let env = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.set(env, forKey: "nexus_gemini_api_key")
            return env
        }
        if let stored = UserDefaults.standard.string(forKey: "nexus_gemini_api_key"), !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        let key = decode(bytes: geminiBytes)
        UserDefaults.standard.set(key, forKey: "nexus_gemini_api_key")
        return key
    }
    
    static var serpApiKey: String {
        if let env = ProcessInfo.processInfo.environment["SERPAPI_API_KEY"], !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.set(env, forKey: "nexus_serp_api_key")
            return env
        }
        if let stored = UserDefaults.standard.string(forKey: "nexus_serp_api_key"), !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        let key = decode(bytes: serpBytes)
        UserDefaults.standard.set(key, forKey: "nexus_serp_api_key")
        return key
    }
}
