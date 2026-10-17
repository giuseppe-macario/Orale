// GPTService.swift

import Foundation

struct GPTService {

    // MARK: - Config

    private enum Config {
        static let url = URL(
            string: "https://api.openai.com/v1/responses"
        )!

        static let model = Configuration.model

        static let validationURL = URL(
            string: "https://api.openai.com/v1/models/\(model)"
        )!
    }
    
    private static var configuredAPIKey: String? {
        let key = Configuration.apiKey

        guard key.range(
            of: #"^sk-[A-Za-z0-9_-]+$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }

        return key
    }

    // MARK: - Public API

    var isAPIKeyConfigured: Bool {
        Self.configuredAPIKey != nil
    }
    
    func validateConfiguredModel() async throws {
        guard let apiKey = Self.configuredAPIKey else {
            throw GPTServiceError.missingAPIKey
        }

        var request = URLRequest(url: Config.validationURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        request.setValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(
                data: data,
                encoding: .utf8
            ) ?? ""

            let message = Self.parseAPIError(from: errorBody)
                ?? "Verifica del modello fallita"

            throw GPTServiceError.http(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    func stream(
        prompt: String
    ) -> AsyncThrowingStream<String, Error> {

        Self.stream(
            prompt: prompt,
            systemPrompt: Configuration.mainPrompt,
            reasoningEffort: Configuration.mainReasoningEffort
        )
    }

    func streamShort(
        prompt: String
    ) -> AsyncThrowingStream<String, Error> {

        Self.stream(
            prompt: prompt,
            systemPrompt: Configuration.shortPrompt,
            reasoningEffort: Configuration.shortReasoningEffort
        )
    }

    // MARK: - Shared Streaming Implementation

    private static func stream(
        prompt: String,
        systemPrompt: String,
        reasoningEffort: String
    ) -> AsyncThrowingStream<String, Error> {

        AsyncThrowingStream { continuation in

            guard let apiKey = Self.configuredAPIKey else {
                continuation.finish(
                    throwing: GPTServiceError.missingAPIKey
                )
                return
            }

            let task = Task {
                do {

                    // MARK: Request Body

                    let body = Request(
                        model: Config.model,
                        reasoning: .init(
                            effort: reasoningEffort
                        ),
                        input: [
                            .system(systemPrompt),
                            .user(prompt)
                        ],
                        stream: true
                    )

                    // MARK: HTTP Request

                    var request = URLRequest(url: Config.url)

                    request.httpMethod = "POST"

                    request.setValue(
                        "Bearer \(apiKey)",
                        forHTTPHeaderField: "Authorization"
                    )

                    request.setValue(
                        "application/json",
                        forHTTPHeaderField: "Content-Type"
                    )

                    request.httpBody =
                        try JSONEncoder().encode(body)

                    // MARK: Streaming Response

                    let (bytes, response) =
                        try await URLSession.shared.bytes(
                            for: request
                        )

                    // MARK: HTTP Errors

                    if let httpResponse = response as? HTTPURLResponse,
                       !(200...299).contains(httpResponse.statusCode) {

                        var errorBody = ""

                        for try await line in bytes.lines {
                            errorBody += line
                        }

                        let message =
                            Self.parseAPIError(from: errorBody)
                            ?? "Richiesta fallita. HTTP \(httpResponse.statusCode)"

                        throw GPTServiceError.http(
                            statusCode: httpResponse.statusCode,
                            message: message
                        )
                    }

                    // MARK: SSE Events

                    let decoder = JSONDecoder()
                    var receivedCompletedEvent = false

                    for try await line in bytes.lines {

                        guard line.hasPrefix("data: ") else {
                            continue
                        }

                        let jsonString = String(
                            line.dropFirst("data: ".count)
                        )

                        if jsonString == "[DONE]" {
                            break
                        }

                        guard let data = jsonString.data(
                            using: .utf8
                        ) else {
                            continue
                        }

                        let event = try decoder.decode(
                            StreamEvent.self,
                            from: data
                        )

                        switch event.type {

                        case "response.output_text.delta":
                            if let delta = event.delta {
                                continuation.yield(delta)
                            }

                        case "response.completed":
                            receivedCompletedEvent = true

                        case "response.failed":
                            let message =
                                event.response?.error?.message
                                ?? event.error?.message
                                ?? event.message
                                ?? "Errore non specificato"

                            throw GPTServiceError.responseFailed(
                                message
                            )

                        case "response.incomplete":
                            let reason =
                                event.response?.incompleteDetails?.reason
                                ?? "Motivo non specificato"

                            throw GPTServiceError.responseIncomplete(
                                reason
                            )

                        case "error":
                            let message =
                                event.error?.message
                                ?? event.message
                                ?? "Errore durante lo streaming"

                            throw GPTServiceError.responseFailed(
                                message
                            )

                        default:
                            break
                        }

                        if receivedCompletedEvent {
                            break
                        }
                    }

                    // La connessione da sola non prova che la risposta
                    // sia stata completata correttamente.

                    guard receivedCompletedEvent else {
                        throw GPTServiceError.connectionEndedPrematurely
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { termination in

                if case .cancelled = termination {
                    task.cancel()
                }
            }
        }
    }

    // MARK: - Error Parsing

    private static func parseAPIError(
        from json: String
    ) -> String? {

        guard let data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder()
            .decode(APIError.self, from: data)
            .error
            .message
    }
}

// MARK: - Request Models

private struct Request: Encodable {

    let model: String
    let reasoning: Reasoning
    let input: [Message]
    let stream: Bool

    struct Reasoning: Encodable {
        let effort: String
    }

    struct Message: Encodable {

        let role: Role
        let content: [Content]

        static func system(_ text: String) -> Self {
            .init(
                role: .system,
                content: [
                    .text(text)
                ]
            )
        }

        static func user(_ text: String) -> Self {
            .init(
                role: .user,
                content: [
                    .text(text)
                ]
            )
        }
    }

    struct Content: Encodable {

        let type: ContentType
        let text: String

        static func text(_ value: String) -> Self {
            .init(
                type: .inputText,
                text: value
            )
        }
    }

    enum Role: String, Encodable {
        case system
        case user
    }

    enum ContentType: String, Encodable {
        case inputText = "input_text"
    }
}

// MARK: - Streaming Event

private struct StreamEvent: Decodable {

    let type: String
    let delta: String?
    let message: String?
    let error: StreamErrorInfo?
    let response: StreamResponseInfo?
}

private struct StreamErrorInfo: Decodable {
    let message: String?
}

private struct StreamResponseInfo: Decodable {

    let error: StreamErrorInfo?
    let incompleteDetails: StreamIncompleteDetails?

    enum CodingKeys: String, CodingKey {
        case error
        case incompleteDetails = "incomplete_details"
    }
}

private struct StreamIncompleteDetails: Decodable {
    let reason: String?
}

// MARK: - API Error

private struct APIError: Decodable {

    let error: Detail

    struct Detail: Decodable {
        let message: String
    }
}
