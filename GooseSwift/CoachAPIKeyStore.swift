import Foundation

/// Stores the user's free-tier Gemini API key. Replaces the previous ChatGPT
/// OAuth/Codex embedded-auth flow: the coach now talks to the Google Gemini API
/// directly with a user-supplied key, so there is no device-code login.
enum CoachAPIKeyStore {
  private static let defaultsKey = "goose.coach.gemini.apiKey"

  static func load() -> String? {
    let value = UserDefaults.standard
      .string(forKey: defaultsKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value, !value.isEmpty else {
      return nil
    }
    return value
  }

  static func save(_ value: String) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      clear()
    } else {
      UserDefaults.standard.set(trimmed, forKey: defaultsKey)
    }
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: defaultsKey)
  }
}
