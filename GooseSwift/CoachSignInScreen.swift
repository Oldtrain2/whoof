import SwiftUI

struct CoachSignInScreen: View {
  let loginStatus: String
  let errorMessage: String?
  let saveKey: (String) -> Void

  @State private var apiKeyDraft = ""

  private let consoleURL = URL(string: "https://aistudio.google.com/app/apikey")

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: "sparkles")
            .font(.title2.weight(.bold))
            .foregroundStyle(.blue)
            .frame(width: 42, height: 42)
            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: WhoofTheme.cardRadius, style: .continuous))

          Text("Connect Coach")
            .font(.title2.bold())
          Text("Coach uses Google Gemini's free tier. Paste a free API key to stream replies and local Whoof tool calls.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .healthCardSurface()

        VStack(alignment: .leading, spacing: 12) {
          CoachStatusLine(title: "Status", value: loginStatus)

          SecureField("Gemini API key", text: $apiKeyDraft)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { saveKey(apiKeyDraft) }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

          if let consoleURL {
            Link(destination: consoleURL) {
              Label("Get a free key in Google AI Studio", systemImage: "arrow.up.right.square")
                .font(.footnote.weight(.semibold))
            }
          }

          if let errorMessage, !errorMessage.isEmpty {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
              .font(.footnote)
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)
          }

          Button {
            saveKey(apiKeyDraft)
          } label: {
            Label("Save key", systemImage: "key.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

          Text("The key is stored on this device. Coach sends your question plus bounded local tool output to Gemini.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .healthCardSurface()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
  }
}

private struct CoachStatusLine: View {
  let title: String
  let value: String

  var body: some View {
    HStack {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
  }
}
