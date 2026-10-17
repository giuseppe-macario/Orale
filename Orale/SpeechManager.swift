// SpeechManager.swift

import Speech
import Combine
import UIKit

final class SpeechManager: NSObject, ObservableObject {

    // MARK: - Proprietà Speech-to-Text

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recordingCompletion: ((String) -> Void)?

    // Notifica il ViewModel in caso di interruzione imprevista.
    var onRecordingError: (() -> Void)?

    @Published var transcript = ""

    private var isRecording = false
    private var isStartingRecording = false
    private var isAudioTapInstalled = false

    // MARK: - Proprietà Text-to-Speech

    private let speechRate: Float = 0.04
    private let speechVolume: Float = 1.0
    private let speechDelay: TimeInterval = 1.5

    private let speechVoice = AVSpeechSynthesisVoice(
        identifier: "com.apple.voice.premium.it-IT.Federica"
    )

    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let synthesizer = AVSpeechSynthesizer()

    private let mainSpeechQueue = SpeechQueue()
    private let shortSpeechQueue = SpeechQueue()

    private enum ActiveSpeechQueue {
        case main
        case short
    }

    private var activeSpeechQueue: ActiveSpeechQueue = .main
    private var pendingSpeechDelay: DispatchWorkItem?

    private var currentInformationalSpeechCompletion: (() -> Void)?
    private var responseFinished: (() -> Void)?
    private var shortResponseFinished: (() -> Void)?

    private var activeUtterance: AVSpeechUtterance?
    @Published var currentMainSentence = ""

    // MARK: - Stato della risposta e ripresa della lettura

    private var isStreamingFinished = false

    private var mainResumeText: String?
    private var shouldPrefixNextMainSentenceWithDicevamo = false

    // MARK: - Init

    override init() {
        super.init()

        synthesizer.delegate = self
        configureAudioSession()
        hapticGenerator.prepare()
    }

    // MARK: - Configurazione audio

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .default)

            session.activate(options: []) { success, error in
                if let error {
                    AppErrorHandler.log(error, context: "Attivazione della sessione audio")
                    return
                }

                if !success {
                    AppErrorHandler.log("Impossibile attivare la sessione audio.", context: "Sessione audio")
                }
            }
        } catch {
            AppErrorHandler.log(error, context: "Configurazione della sessione audio")
        }
    }

    // MARK: - Speech-to-Text

    private func failStartingRecording(_ message: String) {
        AppErrorHandler.log(message, context: "Avvio della registrazione")
        cleanupAudioCapture(cancelRecognition: true)
        onRecordingError?()
    }

    func startRecording() {
        guard !isRecording, !isStartingRecording else { return }

        transcript = ""

        guard let recognizer, recognizer.isAvailable else {
            failStartingRecording("Riconoscimento vocale non disponibile")
            return
        }

        isStartingRecording = true

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let session = AVAudioSession.sharedInstance()

        session.activate(options: []) { [weak self] success, error in
            guard let manager = self else { return }

            Task { @MainActor in
                guard manager.isStartingRecording else { return }

                if let error {
                    AppErrorHandler.log(error, context: "Attivazione audio prima della registrazione")
                    manager.cleanupAudioCapture(cancelRecognition: true)
                    manager.onRecordingError?()
                    return
                }

                guard success else {
                    manager.failStartingRecording("Impossibile attivare la sessione audio")
                    return
                }

                do {
                    try inputNode.installAudioTap(
                        onBus: 0,
                        bufferSize: 1024,
                        format: format
                    ) { buffer, _ in
                        guard buffer.frameLength > 0 else { return }

                        request.append(
                            AVAudioPCMBuffer(copying: buffer)
                        )
                    }

                    manager.isAudioTapInstalled = true

                    manager.startRecognition(
                        request: request,
                        recognizer: recognizer
                    )

                    manager.audioEngine.prepare()
                    try manager.audioEngine.start()

                    manager.isRecording = true
                    manager.isStartingRecording = false

                } catch {
                    AppErrorHandler.log(error, context: "Avvio della registrazione audio")
                    manager.cleanupAudioCapture(cancelRecognition: true)
                    manager.onRecordingError?()
                }
            }
        }
    }

    func finishRecording(completion: @escaping (String) -> Void) {
        guard recordingCompletion == nil else { return }

        guard isRecording || isStartingRecording else {
            completion(transcript)
            return
        }

        guard recognitionTask != nil else {
            cleanupAudioCapture(cancelRecognition: true)
            completion(transcript)
            return
        }

        recordingCompletion = completion

        cleanupAudioCapture()

        recognitionRequest?.endAudio()
        recognitionTask?.finish()
    }

    func cancelRecording() {
        recordingCompletion = nil
        cleanupAudioCapture(cancelRecognition: true)
    }

    private func startRecognition(
        request: SFSpeechAudioBufferRecognitionRequest,
        recognizer: SFSpeechRecognizer
    ) {
        recognitionTask = recognizer.recognitionTask(
            with: request
        ) { [weak self] result, error in

            let recognizedText = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorMessage = error?.localizedDescription

            Task { @MainActor [weak self] in
                guard let self else { return }

                guard self.isRecording ||
                        self.isStartingRecording ||
                        self.recordingCompletion != nil else {
                    return
                }

                if let recognizedText {
                    self.transcript = recognizedText

                    if isFinal, self.recordingCompletion != nil {
                        self.completeRecording(with: recognizedText)
                        return
                    }
                }

                if let errorMessage {
                    AppErrorHandler.log(errorMessage, context: "Riconoscimento vocale")

                    if self.recordingCompletion != nil {
                        // La registrazione è già stata conclusa normalmente.
                        self.completeRecording(with: self.transcript)
                    } else {
                        // Verifichiamo che fosse effettivamente in corso
                        // una registrazione o il suo avvio.
                        let wasRecording = self.isRecording || self.isStartingRecording

                        self.cleanupAudioCapture(cancelRecognition: true)

                        // Avvisiamo il ViewModel solo per un'interruzione imprevista.
                        if wasRecording {
                            self.onRecordingError?()
                        }
                    }
                }
            }
        }
    }

    private func completeRecording(with text: String) {
        transcript = text

        let completion = recordingCompletion

        recordingCompletion = nil
        recognitionRequest = nil
        recognitionTask = nil

        completion?(text)
    }

    private func cleanupAudioCapture(
        cancelRecognition: Bool = false
    ) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if isAudioTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isAudioTapInstalled = false
        }

        if cancelRecognition {
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
        }

        isRecording = false
        isStartingRecording = false
    }

    // MARK: - Text-to-Speech

    // Seguono le due sotto-sezioni Annunci vocali e Code e controllo della lettura

    // MARK: - Annunci vocali

    private func makeUtterance(
        _ text: String,
        rate: Float? = nil
    ) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)

        utterance.voice = speechVoice
        utterance.volume = speechVolume

        if let rate {
            utterance.rate = rate
        }

        return utterance
    }

    func speakAttendo(
        text: String = "Attendo"
    ) {
        speakInformational(text) { [weak self] in
            self?.startNextIfNeeded()
        }
    }

    func speakRegistro(
        text: String = "Registro",
        onFinished: @escaping () -> Void
    ) {
        speakInformational(
            text,
            onFinished: onFinished
        )
    }

    private func speakInformational(
        _ text: String,
        onFinished: @escaping () -> Void
    ) {
        cancelPendingSpeechDelay()
        currentInformationalSpeechCompletion = onFinished

        let utterance = makeUtterance(text)

        activeUtterance = utterance
        synthesizer.speak(utterance)

        hapticGenerator.impactOccurred()
        hapticGenerator.prepare()
    }

    // MARK: - Code e controllo della lettura

    func enqueue(
        sentence: String,
        rate: Float? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        mainSpeechQueue.enqueue(
            text: sentence,
            rate: rate ?? speechRate,
            onFinished: onFinished
        )

        guard !synthesizer.isSpeaking else {
            return
        }

        guard shortSpeechQueue.isEmpty else {
            return
        }

        guard activeSpeechQueue == .main else {
            return
        }

        startNextIfNeeded()
    }

    func enqueueShort(
        sentence: String,
        rate: Float? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        shortSpeechQueue.enqueue(
            text: sentence,
            rate: rate ?? speechRate,
            onFinished: onFinished
        )

        activeSpeechQueue = .short
        startNextIfNeeded()
    }

    private func startNextIfNeeded() {
        guard pendingSpeechDelay == nil else {
            return
        }

        // Evita di avviare una nuova frase mentre un'utterance è attiva.
        // isSpeaking può aggiornarsi con un leggero ritardo.
        guard activeUtterance == nil else {
            return
        }

        guard !synthesizer.isSpeaking else {
            return
        }

        let queue: SpeechQueue

        switch activeSpeechQueue {
        case .main:
            queue = mainSpeechQueue

        case .short:
            queue = shortSpeechQueue
        }

        guard !queue.isPaused else {
            return
        }

        guard let next = queue.next() else {
            switch activeSpeechQueue {
            case .main:
                if isStreamingFinished {
                    transcript = ""
                    responseFinished?()
                    responseFinished = nil
                }

            case .short:
                shortResponseFinished?()
                shortResponseFinished = nil
            }

            return
        }

        let utteranceText: String

        if activeSpeechQueue == .main &&
            shouldPrefixNextMainSentenceWithDicevamo {

            utteranceText = "Dicevamo: " +
            next.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            shouldPrefixNextMainSentenceWithDicevamo = false

        } else {
            utteranceText = next.text
        }

        let utterance = makeUtterance(
            utteranceText,
            rate: next.rate
        )

        activeUtterance = utterance
        synthesizer.speak(utterance)
    }

    func togglePauseSpeaking() -> Bool {
        let queue: SpeechQueue

        switch activeSpeechQueue {
        case .main:
            queue = mainSpeechQueue
        case .short:
            queue = shortSpeechQueue
        }

        if queue.isPaused {

            if activeSpeechQueue == .short {
                guard synthesizer.continueSpeaking() else {
                    return false
                }

                queue.resume()
                return true
            }

            guard let current = queue.currentItem else {
                queue.resume()
                startNextIfNeeded()
                return true
            }

            synthesizer.stopSpeaking(at: .immediate)

            let utterance = makeUtterance(
                "Dicevamo: " + current.text,
                rate: current.rate
            )

            queue.resume()

            activeUtterance = utterance
            synthesizer.speak(utterance)
            return true

        } else if synthesizer.isSpeaking,
                  queue.currentItem != nil {

            let boundary: AVSpeechBoundary =
                activeSpeechQueue == .short ? .word : .immediate

            guard synthesizer.pauseSpeaking(at: boundary) else {
                return false
            }

            queue.pause()
            return true
        }

        return false
    }

    func finishStreaming(onFinished: @escaping () -> Void) {
        isStreamingFinished = true
        responseFinished = onFinished
        startNextIfNeeded()
    }

    func finishShortStreaming(onFinished: @escaping () -> Void) {
        shortResponseFinished = onFinished
        startNextIfNeeded()
    }

    private func cancelPendingSpeechDelay() {
        pendingSpeechDelay?.cancel()
        pendingSpeechDelay = nil
    }

    func stopSpeaking() {
        cancelPendingSpeechDelay()

        mainSpeechQueue.clear()
        shortSpeechQueue.clear()

        currentInformationalSpeechCompletion = nil
        responseFinished = nil
        shortResponseFinished = nil

        activeUtterance = nil
        currentMainSentence = ""
        activeSpeechQueue = .main

        isStreamingFinished = false

        mainResumeText = nil
        shouldPrefixNextMainSentenceWithDicevamo = false

        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Interruzione e ripresa della lettura principale

    func interruptMainSpeech() {
        guard activeSpeechQueue == .main else {
            return
        }

        // Salva la frase corrente, se ce n'è una.
        mainResumeText = mainSpeechQueue.currentItem?.text

        // Se non c'è una frase corrente, l'interruzione avviene
        // tipicamente durante la pausa tra due frasi.
        shouldPrefixNextMainSentenceWithDicevamo =
        (mainResumeText == nil)

        cancelPendingSpeechDelay()
        activeSpeechQueue = .short

        guard synthesizer.isSpeaking else {
            return
        }

        activeUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func stopShortSpeech() {
        guard activeSpeechQueue == .short else {
            return
        }

        activeUtterance = nil

        shortSpeechQueue.clear()
        shortResponseFinished = nil

        synthesizer.stopSpeaking(at: .immediate)

        activeSpeechQueue = .main
    }

    func resumeMainSpeech() {
        cancelPendingSpeechDelay()

        activeSpeechQueue = .main
        mainSpeechQueue.resume()

        let textToResume = mainResumeText
        ?? mainSpeechQueue.currentItem?.text

        mainResumeText = nil

        guard let textToResume else {
            // Il flag rimane attivo se l'interruzione è avvenuta
            // durante la pausa tra due frasi.
            startNextIfNeeded()
            return
        }

        // La frase interrotta viene ripetuta con il prefisso qui.
        // Evita quindi di aggiungere un secondo prefisso alla frase seguente.
        shouldPrefixNextMainSentenceWithDicevamo = false

        synthesizer.stopSpeaking(at: .immediate)

        let utterance = makeUtterance(
            "Dicevamo: " +
            textToResume.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            rate: mainSpeechQueue.currentItem?.rate ?? speechRate
        )

        activeUtterance = utterance
        synthesizer.speak(utterance)
    }

    // MARK: - Prompt di riproduzione

    func showPlaybackPrompt(for prompt: String) {
        transcript = prompt
    }

    // MARK: - Completamento della sintesi vocale

    private func handleSpeechFinished(
        _ utterance: AVSpeechUtterance
    ) {
        guard let activeUtterance,
              utterance === activeUtterance else {
            return
        }

        self.activeUtterance = nil

        if let completion = currentInformationalSpeechCompletion {
            currentInformationalSpeechCompletion = nil
            completion()
            return
        }

        if activeSpeechQueue == .main {
            currentMainSentence = ""
        }

        let queue: SpeechQueue

        switch activeSpeechQueue {
        case .main:
            queue = mainSpeechQueue

        case .short:
            queue = shortSpeechQueue
        }

        queue.finishCurrent()

        cancelPendingSpeechDelay()

        switch activeSpeechQueue {
        case .main:
            let workItem = DispatchWorkItem {
                self.pendingSpeechDelay = nil
                self.startNextIfNeeded()
            }

            pendingSpeechDelay = workItem

            DispatchQueue.main.asyncAfter(
                deadline: .now() + speechDelay,
                execute: workItem
            )

        case .short:
            if shortSpeechQueue.isEmpty {
                let completion = shortResponseFinished
                shortResponseFinished = nil

                activeSpeechQueue = .main

                let workItem = DispatchWorkItem {
                    self.pendingSpeechDelay = nil
                    completion?()
                }

                pendingSpeechDelay = workItem

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + speechDelay * 2,
                    execute: workItem
                )

                return
            }

            startNextIfNeeded()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechManager: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        guard utterance === activeUtterance,
              activeSpeechQueue == .main,
              currentInformationalSpeechCompletion == nil else {
            return
        }

        var sentence = utterance.speechString
        let prefix = "Dicevamo: "

        if sentence.hasPrefix(prefix) {
            sentence.removeFirst(prefix.count)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.activeSpeechQueue == .main,
                  self.activeUtterance === utterance else {
                return
            }

            self.currentMainSentence = sentence
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        handleSpeechFinished(utterance)
    }
}
