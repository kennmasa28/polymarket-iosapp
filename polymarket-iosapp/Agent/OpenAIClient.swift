//
//  OpenAIClient.swift
//  polymarket-iosapp
//
//  OpenAI Chat Completions API（Structured Outputs）で売買判断を取得する。
//  API キーは Keychain（KeychainItem.openAIKey）に保存し、設定ファイルには書かない。
//

import Foundation

nonisolated enum OpenAIError: LocalizedError {
    case missingAPIKey
    case emptyResponse
    case refusal(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "OpenAI の API キーが設定されていません"
        case .emptyResponse: "AI から判断が返りませんでした"
        case .refusal(let message): "AI が回答を拒否しました: \(message)"
        }
    }
}

nonisolated struct OpenAIChatResponse: Decodable {
    nonisolated struct Choice: Decodable {
        nonisolated struct Message: Decodable {
            let content: String?
            let refusal: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

nonisolated struct OpenAIClient: Sendable {
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    var http = HTTPClient()

    static func loadAPIKey() -> String? {
        guard let data = try? KeychainItem.openAIKey.load(),
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }
        return key
    }

    func decide(model: String, systemPrompt: String, userPrompt: String) async throws -> AgentDecision {
        guard let apiKey = Self.loadAPIKey() else { throw OpenAIError.missingAPIKey }
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "trading_decision",
                    "strict": true,
                    "schema": AgentDecision.jsonSchema,
                ] as [String: Any],
            ] as [String: Any],
        ]
        let data = try await http.send(
            "POST", url: Self.endpoint,
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: try JSONSerialization.data(withJSONObject: body),
            timeout: 90)

        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let message = response.choices.first?.message else { throw OpenAIError.emptyResponse }
        if let refusal = message.refusal, !refusal.isEmpty { throw OpenAIError.refusal(refusal) }
        guard let content = message.content, !content.isEmpty else { throw OpenAIError.emptyResponse }
        return try JSONDecoder().decode(AgentDecision.self, from: Data(content.utf8))
    }
}
