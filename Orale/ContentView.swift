// ContentView.swift

import SwiftUI

struct ContentView: View {

    // MARK: - Stato
    
    @StateObject private var speechManager = SpeechManager()
    @State private var responseText = ""
    @State private var mainPrompt = ""
    
    private enum AppState {
        case idle
        case recording
        case responding
        case shortRecording
        case shortResponding
    }

    @State private var appState: AppState = .idle
    @State private var isStartingRecording = false
    @State private var mainStreamingTask: Task<Void, Never>?
    @State private var shortStreamingTask: Task<Void, Never>?
    
    // MARK: - View principale

    var body: some View {
        VStack(spacing: 16) {
            transcriptArea     // Area di trascrizione vocale
            responseArea       // Area di risposta GPT
            mainButtonArea     // Pulsante principale e zona tappabile
        }
        .padding()
    }

    // MARK: - Sub-Views
    
    private var transcriptArea: some View {
        ZStack {
            Color.gray.opacity(0.1)
                .cornerRadius(12)
                .contentShape(Rectangle())
                .onTapGesture {
                    speechManager.togglePauseSpeaking()
                }

            TextEditor(text: $speechManager.transcript)
                .font(.system(size: 14))
                .disabled(true)
                .padding()
        }
        .frame(height: 120)
    }
    
    private var responseArea: some View {
        ScrollView {
            Text(responseText)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .frame(maxHeight: 240)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var mainButtonArea: some View {
        VStack(spacing: 0) {

            Button(action: buttonTapped) {
                Text(buttonLabel())
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.borderedProminent)

            Rectangle()
                .foregroundColor(.clear)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            handleDoubleTap()
                        }
                )
                .onTapGesture {
                    handleSingleTap()
                }
        }
    }

    // MARK: - Azioni
    
    @MainActor
    private func buttonTapped() {
        guard !isStartingRecording else {
            return
        }

        switch appState {

        case .idle:
            startRecording()

        case .recording:
            Task {
                await handleStopRecording()
            }

        case .responding:
            speechManager.stopSpeaking()
            mainStreamingTask?.cancel()
            mainStreamingTask = nil

            speechManager.transcript = ""
            responseText = ""

            appState = .idle

        case .shortRecording:
            Task {
                await handleStopShortRecording()
            }

        case .shortResponding:
            stopShortResponse()
        }
    }
    
    @MainActor
    private func handleDoubleTap() {
        guard appState == .responding else {
            return
        }

        startShortRecording()
    }

    @MainActor
    private func handleSingleTap() {
        buttonTapped()
    }
    
    private func handleStopRecording() async {

        speechManager.stopRecording()

        let prompt = speechManager.transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        mainPrompt = prompt

        guard !prompt.isEmpty else {
            responseText = "Nessuna domanda registrata."
            appState = .idle
            return
        }

        speechManager.showPlaybackPrompt(for: prompt)

        responseText = ""
        
        speechManager.isStreamingFinished = false
        appState = .responding
        
        speechManager.speakAttendo()

        mainStreamingTask = Task {
            await streamAnswer(for: prompt)
        }
    }
    
    private func handleStopShortRecording() async {
        speechManager.stopRecording()

        let prompt = speechManager.transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prompt.isEmpty else {
            speechManager.showPlaybackPrompt(for: mainPrompt)
            appState = .responding
            speechManager.resumeMainSpeech()
            return
        }

        appState = .shortResponding
        
        speechManager.speakAttendo(
            text: "Attendo risposta breve"
        )

        shortStreamingTask = Task {
            await streamShortAnswer(for: prompt)
        }
    }
    
    @MainActor
    private func stopShortResponse() {
        shortStreamingTask?.cancel()
        shortStreamingTask = nil
        
        speechManager.stopShortSpeech()
        speechManager.showPlaybackPrompt(for: mainPrompt)
        speechManager.resumeMainSpeech()
        
        appState = .responding
    }
    
    private func startRecording() {
        isStartingRecording = true

        speechManager.stopSpeaking()

        speechManager.speakRegistro {
            speechManager.startRecording()
            isStartingRecording = false
            appState = .recording
        }
    }
    
    @MainActor
    private func startShortRecording() {
        guard appState == .responding else {
            return
        }

        speechManager.interruptMainSpeech()
        speechManager.stopRecording()

        appState = .shortRecording

        speechManager.speakRegistro(
            text: "Registro domanda breve"
        ) {
            speechManager.startRecording()
        }
    }
    
    // MARK: - GPT Streaming
    
    private func streamAnswer(for prompt: String) async {

        var buffer = ""

        do {
            let stream = GPTService.stream(
                prompt: prompt,
                apiKey: Secrets.openAIKey
            )

            for try await delta in stream {

                guard !Task.isCancelled else {
                    return
                }

                buffer += delta

                for sentence in extractSentences(from: &buffer) {

                    guard !Task.isCancelled else {
                        return
                    }

                    await MainActor.run {
                        guard !Task.isCancelled else {
                            return
                        }

                        responseText += sentence
                        speechManager.enqueue(sentence: sentence)
                    }
                }
            }

            guard !Task.isCancelled else {
                return
            }

            if !buffer.isEmpty {
                await MainActor.run {
                    guard !Task.isCancelled else {
                        return
                    }

                    responseText += buffer
                    speechManager.enqueue(sentence: buffer)
                }
            }

        } catch {
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                responseText =
                    "Errore nella chiamata: \(error.localizedDescription)"
            }
        }

        guard !Task.isCancelled else {
            return
        }

        await MainActor.run {
            guard !Task.isCancelled else {
                return
            }

            speechManager.finishStreaming {
                if appState == .responding {
                    appState = .idle
                }
            }

            mainStreamingTask = nil
        }
    }
    
    private func streamShortAnswer(for prompt: String) async {
        var buffer = ""

        do {
            let stream = GPTService.streamShort(
                prompt: prompt,
                apiKey: Secrets.openAIKey
            )

            for try await delta in stream {

                guard !Task.isCancelled else {
                    return
                }

                buffer += delta

                for sentence in extractSentences(from: &buffer) {

                    guard !Task.isCancelled else {
                        return
                    }

                    await MainActor.run {
                        guard !Task.isCancelled else {
                            return
                        }
                        
                        speechManager.enqueueShort(sentence: sentence)
                    }
                }
            }

            guard !Task.isCancelled else {
                return
            }

            if !buffer.isEmpty {
                await MainActor.run {
                    guard !Task.isCancelled else {
                        return
                    }
                    
                    speechManager.enqueueShort(sentence: buffer)
                }
            }

        } catch {
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                print("Errore nella domanda breve: \(error.localizedDescription)")
            }
        }

        guard !Task.isCancelled else {
            return
        }

        await MainActor.run {
            guard !Task.isCancelled else {
                return
            }

            speechManager.finishShortStreaming {
                if appState == .shortResponding {
                    speechManager.showPlaybackPrompt(for: mainPrompt)
                    speechManager.resumeMainSpeech()
                    appState = .responding
                }
            }

            shortStreamingTask = nil
        }
    }
    
    // MARK: - Helpers
    
    private func buttonLabel() -> String {
        switch appState {

        case .idle:
            return "Registra"

        case .recording:
            return "Fine e invia"

        case .responding:
            return "Ferma riproduzione"

        case .shortRecording:
            return "Fine registrazione breve"

        case .shortResponding:
            return "Fine risposta breve"
        }
    }
    
    private func extractSentences(
        from buffer: inout String
    ) -> [String] {

        var sentences: [String] = []

        while let range = buffer.range(of: ".") {

            sentences.append(
                String(buffer[..<range.upperBound])
            )

            buffer = String(
                buffer[range.upperBound...]
            )
        }

        return sentences
    }
}

// MARK: - Preview

//#Preview {
//    ContentView()
//}
