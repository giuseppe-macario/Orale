// GPTService.swift

import Foundation

struct GPTService {

    // MARK: - Config

    enum Config {

        static let url = URL(string: "https://api.openai.com/v1/responses")!
        static let model = "gpt-6-luna"
        static let reasoningEffort = "high"
        static let verbosity = "medium"

        static let systemPrompt =
            """
            Scrivi un tema universitario sull'argomento indicato dall'utente. La risposta deve contenere più di 600 parole, senza mai ridurre l'approfondimento pur di rispettare altri vincoli formali. Il livello tecnico dei contenuti deve essere elevato, esauriente, rigoroso e appropriato a una preparazione universitaria.

            Interpreta il prompt dell'utente in base al contesto. Il prompt è ottenuto tramite dettatura vocale e può quindi contenere errori di trascrizione, parole deformate, spazi inseriti erroneamente o acronimi trascritti in modo scorretto. Ricostruisci l'intento dell'utente senza soffermarti sugli errori. Per esempio, "ISODOSI" può riferirsi a "ISO/OSI", mentre "di H CP" può riferirsi a "DHCP". Quando una parola o un acronimo non ha senso nel contesto, individua l'interpretazione tecnicamente più plausibile.

            Il tema deve essere letto a voce alta. Deve quindi essere discorsivo, naturale, chiaro e approfondito. Non usare virgolette, elenchi puntati, elenchi numerati, tabelle, intestazioni, formule grafiche, simboli decorativi, Markdown, grassetto o altri elementi pensati principalmente per la lettura visiva. Non usare formule matematiche o notazioni che risultino difficili da leggere e pronunciare. Quando sono necessari numeri, formule, simboli o calcoli, esprimili a parole in una forma naturale e adatta alla lettura ad alta voce.
            
            La punteggiatura deve essere ricca di virgole, con una frequenza molto superiore a quella della prosa accademica ordinaria. Le virgole devono creare pause frequenti per favorire un ritmo calmo e naturale durante la lettura ad alta voce. Usa frequentemente la virgola prima di congiunzioni, inclusa la congiunzione "e", locuzioni congiuntive, preposizioni e altri elementi che introducono una precisazione, una conseguenza, una contrapposizione, una causa o un passaggio logico, soprattutto quando la pausa migliora la comprensione orale. Non interpretare questa istruzione come un permesso di inserire virgole casualmente. La correttezza sintattica ha la precedenza. Usa frasi relativamente brevi e ben collegate. Ogni frase deve avere una lunghezza inferiore a 140 caratteri; non superare mai questo limite di 140 caratteri, fatta eccezione per l'ultima frase che conclude il tema. L'effetto complessivo deve essere quello di un discorso molto cadenzato, con numerose pause, ma comunque fluido, naturale e grammaticalmente corretto.
            
            Concentrati direttamente sulla domanda posta. Spiega i concetti necessari per fornire una risposta tecnicamente solida e coerente. Approfondisci cause, funzionamento, caratteristiche, vantaggi, limiti. Collega con altri concetti solo quando sono pertinenti alla domanda e contribuiscono effettivamente alla comprensione della risposta.

            Organizza implicitamente il tema in tre parti: un'introduzione, lo sviluppo dei concetti, e una conclusione. Non indicare esplicitamente queste tre parti con titoli o etichette, ma fai emergere chiaramente la progressione del discorso attraverso collegamenti naturali tra le idee. L'introduzione del tema può essere al massimo di due frasi. La conclusione del tema deve iniziare con "Quindi, per concludere, " e deve essere di una sola frase, che però può superare il limite di 140 caratteri.

            Usa un linguaggio tecnico preciso ma naturale e comprensibile. Privilegia i termini italiani quando sono appropriati. Evita i termini inglesi se possibile: per esempio, sostituisci espressioni come "high-performance server setup" con formulazioni italiane come "configurazione di server ad alte prestazioni". Mantieni invece i termini tecnici internazionalmente consolidati se non esiste un corrispondente italiano.

            Non commentare il prompt dell'utente, non segnalare gli errori di trascrizione e non spiegare le correzioni effettuate. Produci direttamente la risposta alla domanda.
            
            Dai priorità, nell'ordine, a correttezza tecnica, comprensione dell'intento dell'utente, pertinenza rispetto alla domanda, lunghezza delle frasi, correttezza grammaticale e della punteggiatura, chiarezza espositiva, naturalezza per la lettura ad alta voce, stile discorsivo e completezza.
            """
        
        static let shortSystemPrompt =
            """
            Rispondi esclusivamente con una definizione, un enunciato o una formulazione essenziale della nozione richiesta.

            Interpreta il prompt dell'utente in base al contesto. Il prompt è ottenuto tramite dettatura vocale e può quindi contenere errori di trascrizione, parole deformate, spazi inseriti erroneamente o acronimi trascritti in modo scorretto. Ricostruisci l'intento dell'utente senza soffermarti sugli errori. Quando una parola o un acronimo non ha senso nel contesto, individua l'interpretazione tecnicamente più plausibile.

            Se l'utente chiede una legge, un teorema, un principio, una regola o un enunciato, fornisci direttamente il suo enunciato corretto.

            Se l'utente chiede "cos'è", "che cos'è", "definisci" o una domanda equivalente, fornisci una definizione breve, precisa e completa.

            Non aggiungere spiegazioni, esempi, applicazioni, contesto storico o approfondimenti, salvo quando siano indispensabili per rendere corretta la definizione o l'enunciato.

            Non introdurre la risposta con formule come "Certo", "La definizione è", "Si tratta di" o simili. Produci direttamente la risposta.

            La risposta deve essere normalmente costituita da una sola frase, oppure da due frasi quando una sola frase non è sufficiente. Deve essere il più breve possibile senza perdere il significato essenziale.

            Usa un italiano naturale, tecnicamente preciso e adatto alla lettura ad alta voce. Non usare virgolette, elenchi puntati, elenchi numerati, tabelle, intestazioni, formule grafiche, simboli decorativi, Markdown, grassetto o altri elementi pensati principalmente per la lettura visiva. Non usare mai formule matematiche, equazioni, espressioni algebriche, simboli matematici o notazioni scientifiche. Se una risposta richiederebbe una formula, esprimine esclusivamente il significato a parole, senza riportare la formula stessa. Non scrivere sequenze come "a = …", "x²", "E = mc²", frazioni, radici, integrali, somme, simboli di confronto o altre forme di notazione matematica. Anche quando l'utente chiede esplicitamente la formula, fornisci soltanto la sua formulazione verbale, senza riportarla graficamente. I numeri possono essere usati solo quando sono indispensabili all'enunciato e devono essere espressi in forma discorsiva, naturale e adatta alla lettura ad alta voce.

            Dai priorità, nell'ordine, a comprensione dell'intento dell'utente, correttezza tecnica, pertinenza, precisione e brevità.
            """
    }

    // MARK: - Public API

    /// Esegue una richiesta streaming alla Responses API.
    ///
    /// - Parameters:
    ///   - prompt: Testo trascritto da inviare al modello.
    ///   - apiKey: Chiave API OpenAI.
    ///
    /// - Returns:
    ///   Uno stream asincrono contenente i frammenti testuali
    ///   prodotti progressivamente dal modello.
    static func stream(
        prompt: String,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {

        AsyncThrowingStream { continuation in

            Task {
                do {

                    // MARK: Request body

                    let body = Request(
                        model: Config.model,
                        reasoning: .init(
                            effort: Config.reasoningEffort
                        ),
                        text: .init(
                            verbosity: Config.verbosity
                        ),
                        input: [
                            .system(Config.systemPrompt),
                            .user(prompt)
                        ],
                        stream: true
                    )

                    // MARK: HTTP request

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

                    // MARK: Streaming response

                    let (bytes, response) =
                        try await URLSession.shared.bytes(
                            for: request
                        )

                    // MARK: HTTP errors

                    if let httpResponse =
                        response as? HTTPURLResponse,
                        !(200...299).contains(httpResponse.statusCode) {

                        var errorBody = ""

                        for try await line in bytes.lines {
                            errorBody += line
                        }

                        let message =
                            parseAPIError(from: errorBody)
                            ?? "Richiesta fallita. HTTP \(httpResponse.statusCode)."

                        throw NSError(
                            domain: "GPTService",
                            code: httpResponse.statusCode,
                            userInfo: [
                                NSLocalizedDescriptionKey: message
                            ]
                        )
                    }

                    // MARK: SSE events

                    let decoder = JSONDecoder()

                    for try await line in bytes.lines {

                        // Ignora le righe che non sono eventi SSE "data".
                        guard line.hasPrefix("data: ") else {
                            continue
                        }

                        let jsonString = String(
                            line.dropFirst("data: ".count)
                        )

                        // Fine dello stream.
                        if jsonString == "[DONE]" {
                            break
                        }

                        guard let data =
                            jsonString.data(using: .utf8)
                        else {
                            continue
                        }

                        let event =
                            try decoder.decode(
                                StreamEvent.self,
                                from: data
                            )

                        // Evento principale per il testo prodotto.
                        if event.type ==
                            "response.output_text.delta" {

                            if let delta = event.delta {
                                continuation.yield(delta)
                            }
                        }

                        // Eventuali errori restituiti come evento SSE.
                        if event.type == "error" {

                            let message =
                                event.message
                                ?? "Errore durante lo streaming."

                            throw NSError(
                                domain: "GPTService",
                                code: -1,
                                userInfo: [
                                    NSLocalizedDescriptionKey: message
                                ]
                            )
                        }
                    }

                    continuation.finish()

                } catch {

                    continuation.finish(
                        throwing: error
                    )
                }
            }
        }
    }
    
    static func streamShort(
        prompt: String,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {

        AsyncThrowingStream { continuation in

            Task {
                do {

                    let body = Request(
                        model: Config.model,
                        reasoning: .init(
                            effort: Config.reasoningEffort
                        ),
                        text: .init(
                            verbosity: Config.verbosity
                        ),
                        input: [
                            .system(Config.shortSystemPrompt),
                            .user(prompt)
                        ],
                        stream: true
                    )

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

                    let (bytes, response) =
                        try await URLSession.shared.bytes(
                            for: request
                        )

                    if let httpResponse =
                        response as? HTTPURLResponse,
                        !(200...299).contains(httpResponse.statusCode) {

                        var errorBody = ""

                        for try await line in bytes.lines {
                            errorBody += line
                        }

                        let message =
                            parseAPIError(from: errorBody)
                            ?? "Richiesta fallita. HTTP \(httpResponse.statusCode)."

                        throw NSError(
                            domain: "GPTService",
                            code: httpResponse.statusCode,
                            userInfo: [
                                NSLocalizedDescriptionKey: message
                            ]
                        )
                    }

                    let decoder = JSONDecoder()

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

                        guard let data =
                            jsonString.data(using: .utf8)
                        else {
                            continue
                        }

                        let event =
                            try decoder.decode(
                                StreamEvent.self,
                                from: data
                            )

                        if event.type ==
                            "response.output_text.delta" {

                            if let delta = event.delta {
                                continuation.yield(delta)
                            }
                        }

                        if event.type == "error" {

                            let message =
                                event.message
                                ?? "Errore durante lo streaming."

                            throw NSError(
                                domain: "GPTService",
                                code: -1,
                                userInfo: [
                                    NSLocalizedDescriptionKey: message
                                ]
                            )
                        }
                    }

                    continuation.finish()

                } catch {

                    continuation.finish(
                        throwing: error
                    )
                }
            }
        }
    }
    
    // MARK: - Error parsing

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
    let text: TextConfiguration
    let input: [Message]
    let stream: Bool

    struct Reasoning: Encodable {
        let effort: String
    }

    struct TextConfiguration: Encodable {
        let verbosity: String
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

    // Presente negli eventi response.output_text.delta
    let delta: String?

    // Presente negli eventi di errore
    let message: String?
}

// MARK: - API Error

private struct APIError: Decodable {

    let error: Detail

    struct Detail: Decodable {
        let message: String
    }
}
