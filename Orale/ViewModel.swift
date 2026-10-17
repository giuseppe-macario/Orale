// ViewModel.swift

import Foundation
import Combine

@MainActor
final class ViewModel: ObservableObject {

    // MARK: - Stato e proprietà

    enum AppState {
        case idle
        case recording
        case responding
        case shortRecording
        case shortResponding
    }

    let speechManager: SpeechManager

    private let gptService = GPTService()

    @Published private(set) var gptValidationStatus:
        ProviderValidationStatus = .checking

    var isGPTAvailable: Bool {
        gptValidationStatus == .valid
    }

    var isMainButtonDisabled: Bool {
        isPreparingRecording ||
        (appState == .idle && !isGPTAvailable)
    }

    @Published var responseText = ""
    private var mainPrompt = ""
    @Published var appState: AppState = .idle
    @Published var isPreparingRecording = false
    @Published var isGeneratingMainResponse = false
    @Published private var hasStartedMainPlayback = false
    @Published var isGeneratingShortResponse = false
    @Published var hasStarted = false
    @Published var shortExchangeText = ""
    @Published var isMainSpeechPaused = false
    @Published var isShortSpeechPaused = false

    private var mainStreamingTask: Task<Void, Never>?
    private var shortStreamingTask: Task<Void, Never>?
    private var mainResponseText = ""

    var shouldShowMainPlaybackPrompt: Bool {
        !isGeneratingMainResponse || hasStartedMainPlayback
    }

    // MARK: - Init

    init(speechManager: SpeechManager) {
        self.speechManager = speechManager

        speechManager.onRecordingError = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                switch self.appState {
                case .recording:
                    // La registrazione principale si è interrotta.
                    self.isPreparingRecording = false
                    self.appState = .idle

                case .shortRecording:
                    // La domanda breve si è interrotta:
                    // riprendiamo la risposta principale.
                    self.isPreparingRecording = false
                    self.resumeMainResponseAfterShortInteraction()

                default:
                    // Se l'app è già passata a un altro stato,
                    // non modifichiamo nulla.
                    return
                }
            }
        }

        Task { [weak self] in
            await self?.validateGPT()
        }
    }

    private func validateGPT() async {
        guard gptService.isAPIKeyConfigured else {
            gptValidationStatus = .missingAPIKey
            return
        }

        gptValidationStatus = .checking

        do {
            try await gptService.validateConfiguredModel()
            gptValidationStatus = .valid

        } catch {
            AppErrorHandler.log(error, context: "Verifica iniziale del modello OpenAI")

            gptValidationStatus =
                AppErrorHandler.validationStatus(
                    for: error,
                    duringInitialCheck: true
                ) ?? .unavailable
        }
    }

    // MARK: - Stato dell'interfaccia

    var showInitialInstructions: Bool {
        !hasStarted
    }

    var currentStatus: String {
        if isPreparingRecording {
            return "Preparazione della registrazione"
        }

        switch appState {
        case .idle:
            return "Pronto"
        case .recording:
            return "In ascolto"
        case .responding:
            if isMainSpeechPaused {
                return isGeneratingMainResponse
                ? "Genero la risposta (lettura in pausa)"
                : "Riproduzione in pausa"
            }
            if isGeneratingMainResponse {
                return hasStartedMainPlayback
                ? "Genero e riproduco la risposta"
                : "Genero la risposta"
            }
            return "Risposta in riproduzione"
        case .shortRecording:
            return "In ascolto della domanda breve"
        case .shortResponding:
            if isShortSpeechPaused {
                return "Risposta breve in pausa"
            }
            return isGeneratingShortResponse
            ? "Genero risposta breve"
            : "Risposta breve in riproduzione"
        }
    }

    var tapAreaTitle: String {
        switch appState {
        case .responding:
            return """
                   Doppio tap: fai una domanda breve
                   Tap singolo: interrompe e cancella la risposta
                   """
        case .shortResponding:
            return "Tap singolo: interrompe la risposta breve"
        case .recording, .shortRecording:
            return "Tocca il pulsante per terminare la registrazione"
        case .idle:
            return "Tocca il pulsante per iniziare"
        }
    }

    var buttonLabel: String {
        if isPreparingRecording {
            return "Attendi"
        }

        switch appState {
        case .idle:
            return "Registra"
        case .recording:
            return "Termina registrazione"
        case .responding:
            return "Interrompi risposta"
        case .shortRecording:
            return "Termina domanda breve"
        case .shortResponding:
            return "Interrompi risposta breve"
        }
    }

    // MARK: - Azioni dell'interfaccia

    func buttonTapped() {
        guard !isPreparingRecording else {
            return
        }

        if appState == .idle && !isGPTAvailable {
            return
        }

        switch appState {
        case .idle:
            startMainRecording()
        case .recording:
            stopMainRecording()
        case .responding:
            cancelMainResponse()
        case .shortRecording:
            stopShortRecording()
        case .shortResponding:
            stopShortResponse()
        }
    }

    func handleDoubleTap() {
        guard !isPreparingRecording, appState == .responding else { return }
        startShortRecording()
    }

    func handleSingleTap() {
        buttonTapped()
    }

    func togglePauseSpeaking() {
        guard appState == .responding ||
                appState == .shortResponding else {
            return
        }

        guard speechManager.togglePauseSpeaking() else {
            return
        }

        switch appState {
        case .responding:
            isMainSpeechPaused.toggle()

        case .shortResponding:
            isShortSpeechPaused.toggle()

        default:
            break
        }
    }

    // MARK: - Domanda principale

    private func startMainRecording() {
        hasStarted = true
        mainStreamingTask?.cancel()
        shortStreamingTask?.cancel()
        mainStreamingTask = nil
        shortStreamingTask = nil

        speechManager.stopSpeaking()

        responseText = ""
        mainResponseText = ""
        mainPrompt = ""
        shortExchangeText = ""
        isGeneratingMainResponse = false
        hasStartedMainPlayback = false
        isGeneratingShortResponse = false
        isMainSpeechPaused = false
        isPreparingRecording = true
        appState = .recording

        speechManager.speakRegistro { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isPreparingRecording,
                      self.appState == .recording else { return }

                self.speechManager.startRecording()
                self.isPreparingRecording = false
            }
        }
    }

    private func stopMainRecording() {
        speechManager.finishRecording { [weak self] transcript in
            Task { @MainActor [weak self] in
                guard let self,
                      self.appState == .recording else {
                    return
                }

                self.handleMainRecordingFinished(transcript)
            }
        }
    }

    private func handleMainRecordingFinished(_ transcript: String) {
        mainPrompt = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !mainPrompt.isEmpty else {
            speechManager.transcript = ""
            appState = .idle
            return
        }

        speechManager.showPlaybackPrompt(for: mainPrompt)

        appState = .responding
        isGeneratingMainResponse = true

        speechManager.speakAttendo()

        mainStreamingTask = Task { [weak self] in
            guard let self else { return }
            await self.generateMainResponse(for: self.mainPrompt)
        }
    }

    private func generateMainResponse(for prompt: String) async {
        var buffer = ""

        do {
            for try await delta in gptService.stream(
                prompt: prompt
            ) {
                try Task.checkCancellation()
                mainResponseText += delta
                buffer += delta

                if appState != .shortRecording && appState != .shortResponding {
                    responseText = mainResponseText
                }

                for sentence in extractSentences(from: &buffer) {
                    try Task.checkCancellation()
                    speechManager.enqueue(sentence: sentence)
                    hasStartedMainPlayback = true
                }
            }

            try Task.checkCancellation()

            let finalSentence = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalSentence.isEmpty {
                speechManager.enqueue(sentence: finalSentence)
            }
        } catch {
            if Task.isCancelled { return }

            AppErrorHandler.log(error, context: "Generazione della risposta principale")

            if let status = AppErrorHandler.validationStatus(for: error) {
                gptValidationStatus = status
            }

            let nsError = error as NSError
            let errorDescription = error.localizedDescription

            isGeneratingMainResponse = false
            speechManager.stopSpeaking()
            isMainSpeechPaused = false

            responseText = """
            Errore durante la generazione:

            \(errorDescription)

            Dettagli tecnici: \(nsError.domain)
            Codice: \(nsError.code)
            """

            mainResponseText = responseText
            appState = .idle
            mainStreamingTask = nil
            return
        }

        isGeneratingMainResponse = false
        speechManager.finishStreaming { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.appState == .responding {
                    self.appState = .idle
                }
            }
        }
        mainStreamingTask = nil
    }

    private func cancelMainResponse() {
        mainStreamingTask?.cancel()
        shortStreamingTask?.cancel()

        mainStreamingTask = nil
        shortStreamingTask = nil

        speechManager.stopSpeaking()
        speechManager.transcript = ""

        isMainSpeechPaused = false

        isPreparingRecording = false
        isGeneratingMainResponse = false
        isGeneratingShortResponse = false

        shortExchangeText = ""
        mainPrompt = ""
        mainResponseText = ""
        responseText = ""

        appState = .idle
    }

    // MARK: - Domanda breve

    private func startShortRecording() {
        shortStreamingTask?.cancel()
        shortStreamingTask = nil

        speechManager.interruptMainSpeech()
        speechManager.cancelRecording()

        isShortSpeechPaused = false
        isPreparingRecording = true
        appState = .shortRecording
        shortExchangeText = ""

        speechManager.speakRegistro(text: "Registro domanda breve") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isPreparingRecording,
                      self.appState == .shortRecording else { return }

                self.speechManager.startRecording()
                self.isPreparingRecording = false
            }
        }
    }

    private func stopShortRecording() {
        speechManager.finishRecording { [weak self] transcript in
            Task { @MainActor [weak self] in
                guard let self,
                      self.appState == .shortRecording else {
                    return
                }

                self.handleShortRecordingFinished(transcript)
            }
        }
    }

    private func handleShortRecordingFinished(_ transcript: String) {
        let prompt = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !prompt.isEmpty else {
            resumeMainResponseAfterShortInteraction()
            return
        }

        shortExchangeText = "\(prompt)\n"
        appState = .shortResponding
        isGeneratingShortResponse = true

        speechManager.speakAttendo(text: "Attendo risposta breve")

        shortStreamingTask = Task { [weak self] in
            guard let self else { return }
            await self.generateShortResponse(for: prompt)
        }
    }

    private func generateShortResponse(for prompt: String) async {
        var buffer = ""

        do {
            for try await delta in gptService.streamShort(
                prompt: prompt
            ) {
                try Task.checkCancellation()

                shortExchangeText += delta
                buffer += delta
            }

            try Task.checkCancellation()

            let remainingText = buffer.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if !remainingText.isEmpty {
                speechManager.enqueueShort(sentence: remainingText)
            }

        } catch {
            if Task.isCancelled { return }

            AppErrorHandler.log(error, context: "Generazione della risposta breve")

            if let status = AppErrorHandler.validationStatus(for: error) {
                gptValidationStatus = status
            }

            let nsError = error as NSError

            isGeneratingShortResponse = false
            speechManager.stopShortSpeech()

            shortExchangeText += """


            Errore durante la generazione della risposta breve:

            \(error.localizedDescription)

            Dettagli tecnici: \(nsError.domain)
            Codice: \(nsError.code)
            """

            shortStreamingTask = nil

            resumeMainResponseAfterShortInteraction(
                preservingShortExchange: true
            )

            return
        }

        guard !Task.isCancelled else { return }

        isGeneratingShortResponse = false
        speechManager.finishShortStreaming { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.appState == .shortResponding else { return }

                self.resumeMainResponseAfterShortInteraction()
            }
        }

        shortStreamingTask = nil
    }

    private func stopShortResponse() {
        shortStreamingTask?.cancel()
        shortStreamingTask = nil

        speechManager.stopShortSpeech()
        isGeneratingShortResponse = false

        resumeMainResponseAfterShortInteraction()
    }

    private func resumeMainResponseAfterShortInteraction(
        preservingShortExchange: Bool = false
    ) {
        if !preservingShortExchange {
            shortExchangeText = ""
        }

        speechManager.showPlaybackPrompt(for: mainPrompt)
        responseText = mainResponseText

        isMainSpeechPaused = false
        isShortSpeechPaused = false

        speechManager.resumeMainSpeech()
        appState = .responding
    }

    // MARK: - Suddivisione del testo in frasi

    private func extractSentences(from buffer: inout String) -> [String] {
        var sentences: [String] = []

        while let range = buffer.range(
            of: #"[.!?][ \r\n]+"#,
            options: .regularExpression
        ) {
            let sentence = String(buffer[..<range.upperBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !sentence.isEmpty {
                sentences.append(sentence)
            }

            buffer = String(buffer[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return sentences
    }
}
