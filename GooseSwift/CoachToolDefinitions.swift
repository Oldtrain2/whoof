import Foundation

/// Builds Gemini `generateContent` request bodies for the Coach, including the
/// system instruction and the local Whoof tool declarations. Replaces the prior
/// OpenAI/Codex request factory.
enum GeminiCoachRequest {
  static let systemInstruction = """
  You are Whoof Coach inside a user-owned WHOOP companion app. Use the available \
  Whoof tools before making claims about health, activity, capture coverage, or \
  device state. Cite tool names inline for metric claims, keep coaching \
  practical, and say when data is missing. Do not diagnose, prescribe, \
  or infer medical conditions. Prefer one concrete next action when the local \
  data is incomplete.
  """

  /// The four local tools the model may call. Parameters are empty objects: each
  /// tool loads a fixed local snapshot and takes no arguments.
  static let functionDeclarations: [[String: Any]] = [
    declaration(
      name: "load_stats",
      description: "Load the current local Whoof metric snapshot, readiness status, score summaries, live heart-rate summary, and provenance."
    ),
    declaration(
      name: "get_activities",
      description: "Load the current manual activity, activity detection, movement packet, persistence, and route summaries."
    ),
    declaration(
      name: "get_capture_sessions",
      description: "Load local capture, packet import, Rust core/parser status, last parsed frame, and device evidence coverage."
    ),
    declaration(
      name: "get_data_gaps",
      description: "Load the concrete data gaps and next actions that should block or qualify Coach recommendations."
    ),
  ]

  private static func declaration(name: String, description: String) -> [String: Any] {
    [
      "name": name,
      "description": description,
      "parameters": [
        "type": "OBJECT",
        "properties": [String: Any](),
      ],
    ]
  }

  /// A `contents` entry for a user text turn.
  static func userText(_ text: String) -> [String: Any] {
    ["role": "user", "parts": [["text": text]]]
  }

  /// A `contents` entry echoing the model's function call (required between the
  /// call and its response in a multi-turn function-calling exchange).
  static func modelFunctionCall(name: String, arguments: [String: Any]) -> [String: Any] {
    ["role": "model", "parts": [["functionCall": ["name": name, "args": arguments]]]]
  }

  /// A `contents` entry carrying a tool result back to the model. Gemini expects
  /// the function response on a `user`-role turn.
  static func functionResponse(name: String, response: [String: Any]) -> [String: Any] {
    ["role": "user", "parts": [["functionResponse": ["name": name, "response": response]]]]
  }

  /// Assemble a full request body.
  static func body(
    model: String,
    contents: [[String: Any]],
    includeTools: Bool
  ) -> [String: Any] {
    var body: [String: Any] = [
      "system_instruction": ["parts": [["text": systemInstruction]]],
      "contents": contents,
      "generationConfig": [
        "temperature": 0.4,
      ],
    ]
    if includeTools {
      body["tools"] = [["functionDeclarations": functionDeclarations]]
    }
    return body
  }
}
