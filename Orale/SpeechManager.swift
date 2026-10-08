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
    
    // MARK: - Proprietà Text-to-Speech
    
    // ⚙️ Impostazioni
    private let speechRate: Float = 0.04
    private let speechVolume: Float = 1.0
    private let speechDelay: TimeInterval = 1.5 // pausa al termine della frase
    private let voiceIdentifier = "com.apple.voice.premium.it-IT.Federica"
    
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
    
    // MARK: - Stato
    
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var isSpeaking = false
    var isStreamingFinished = false
    
    // MARK: - Init
    
    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
        hapticGenerator.prepare()
    }
    
    // MARK: - Audio
    
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.playAndRecord)
        } catch {
            print("Errore configurazione audio: \(error)")
        }
    }
    
    // MARK: - Speech-to-Text
    
    func startRecording() {
        transcript = ""
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest = request
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let session = AVAudioSession.sharedInstance()
        
        session.activate(options: []) { [weak self] success, error in
            guard let self else { return }
            
            if let error {
                print("Errore attivazione audio: \(error)")
                return
            }
            
            guard success else {
                print("Impossibile attivare la sessione audio")
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
                
                self.audioEngine.prepare()
                try self.audioEngine.start()
                
                Task { @MainActor in
                    self.isRecording = true
                }
            } catch {
                print("Errore avvio registrazione: \(error)")
            }
        }
        
        recognitionTask = recognizer?.recognitionTask(
            with: request
        ) { [weak self] result, error in
            
            guard let self else { return }
            
            if let result {
                Task { @MainActor in
                    guard self.isRecording else { return }
                    
                    self.transcript =
                    result.bestTranscription.formattedString
                }
            }
            
            if let error {
                print("Errore riconoscimento: \(error)")
                
                Task { @MainActor in
                    self.isRecording = false
                }
            }
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }
    
    // MARK: - Text-to-Speech
    
    func speakAttendo(
        text: String = "Attendo"
    ) {
        cancelPendingSpeechDelay()

        currentInformationalSpeechCompletion = {
            self.startNextIfNeeded()
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        utterance.volume = speechVolume

        activeUtterance = utterance
        synthesizer.speak(utterance)
        isSpeaking = true
        
        hapticGenerator.impactOccurred()
        hapticGenerator.prepare()
    }
    
    func speakRegistro(
        text: String = "Registro",
        onFinished: @escaping () -> Void
    ) {
        cancelPendingSpeechDelay()

        currentInformationalSpeechCompletion = onFinished

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        utterance.volume = speechVolume

        activeUtterance = utterance
        synthesizer.speak(utterance)
        isSpeaking = true
        
        hapticGenerator.impactOccurred()
        hapticGenerator.prepare()
    }
    
    func enqueue(
        sentence: String,
        rate: Float? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        
        let effectiveRate = rate ?? speechRate
        
        mainSpeechQueue.enqueue(
            text: sentence,
            rate: effectiveRate,
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
        
        let effectiveRate = rate ?? speechRate
        
        shortSpeechQueue.enqueue(
            text: sentence,
            rate: effectiveRate,
            onFinished: onFinished
        )
        
        guard !synthesizer.isSpeaking else {
            return
        }
        
        activeSpeechQueue = .short
        startNextIfNeeded()
    }
    
    private func startNextIfNeeded() {
        
        guard pendingSpeechDelay == nil else {
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
            isSpeaking = false
            
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
        
        let utterance = AVSpeechUtterance(
            string: next.text
        )
        
        utterance.voice = AVSpeechSynthesisVoice(
            identifier: voiceIdentifier
        )
        
        utterance.volume = speechVolume
        utterance.rate = next.rate

        activeUtterance = utterance
        synthesizer.speak(utterance)

        isSpeaking = true
    }
    
    func togglePauseSpeaking() {
        
        let queue: SpeechQueue
        
        switch activeSpeechQueue {
        case .main:
            queue = mainSpeechQueue
            
        case .short:
            queue = shortSpeechQueue
        }
        
        if queue.isPaused {
            
            guard let current = queue.currentItem else {
                queue.resume()
                startNextIfNeeded()
                return
            }
            
            synthesizer.stopSpeaking(at: .immediate)
            
            let text: String
            
            switch activeSpeechQueue {
            case .main:
                text = "Dicevamo: " + current.text
                
            case .short:
                text = current.text
            }
            
            let utterance = AVSpeechUtterance(
                string: text
            )
            
            utterance.voice = AVSpeechSynthesisVoice(
                identifier: voiceIdentifier
            )
            
            utterance.volume = speechVolume
            utterance.rate = current.rate
            
            queue.resume()
            
            activeUtterance = utterance
            synthesizer.speak(utterance)
            
            isSpeaking = true
            
        } else if synthesizer.isSpeaking,
                  queue.currentItem != nil {
            
            synthesizer.pauseSpeaking(at: .immediate)
            
            queue.pause()
        }
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
    
    func interruptMainSpeech() {
        cancelPendingSpeechDelay()
        
        guard activeSpeechQueue == .main else {
            return
        }
        
        activeSpeechQueue = .short
        
        guard synthesizer.isSpeaking else {
            return
        }
        
        activeUtterance = nil
        
        synthesizer.stopSpeaking(at: .immediate)
        
        isSpeaking = false
    }
    
    func stopShortSpeech() {
        guard activeSpeechQueue == .short else {
            return
        }
        
        activeUtterance = nil
        
        shortSpeechQueue.clear()
        shortResponseFinished = nil
        
        synthesizer.stopSpeaking(at: .immediate)
        
        isSpeaking = false
        activeSpeechQueue = .main
    }
    
    func resumeMainSpeech() {
        
        guard let current = mainSpeechQueue.currentItem else {
            activeSpeechQueue = .main
            startNextIfNeeded()
            return
        }
        
        cancelPendingSpeechDelay()
        
        activeSpeechQueue = .main
        
        mainSpeechQueue.resume()
        
        synthesizer.stopSpeaking(at: .immediate)
        
        let utterance = AVSpeechUtterance(
            string: "Dicevamo: " + current.text
        )
        
        utterance.voice = AVSpeechSynthesisVoice(
            identifier: voiceIdentifier
        )
        
        utterance.volume = speechVolume
        utterance.rate = current.rate

        activeUtterance = utterance
        synthesizer.speak(utterance)

        isSpeaking = true
    }

    func stopSpeaking() {
        cancelPendingSpeechDelay()

        mainSpeechQueue.clear()
        shortSpeechQueue.clear()
        
        currentInformationalSpeechCompletion = nil
        responseFinished = nil
        shortResponseFinished = nil
        
        activeUtterance = nil
        activeSpeechQueue = .main
        
        isStreamingFinished = false
        
        synthesizer.stopSpeaking(at: .immediate)

        isSpeaking = false
    }
    
    // MARK: - Playback
    
    func showPlaybackPrompt(for prompt: String) {
        transcript = "Tap qui per mettere la riproduzione in pausa ⏸️\n" + prompt
    }
    
    // MARK: - Speech completion
    
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
            isSpeaking = false
            completion()
            return
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
                isSpeaking = false
                
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
        didFinish utterance: AVSpeechUtterance
    ) {
        handleSpeechFinished(utterance)
    }
}
