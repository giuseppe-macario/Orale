// ContentView.swift

import SwiftUI

struct ContentView: View {
    @StateObject private var speechManager: SpeechManager
    @StateObject private var viewModel: ViewModel
    
    init() {
        let manager = SpeechManager()
        _speechManager = StateObject(wrappedValue: manager)
        _viewModel = StateObject(
            wrappedValue: ViewModel(speechManager: manager)
        )
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if viewModel.showInitialInstructions {
                initialInstructions
            } else {
                transcriptArea
                responseArea
            }
            
            mainButtonArea
            bottomTapArea
        }
        .padding()
    }
    
    // MARK: - Schermata iniziale
    
    private var initialInstructions: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 42))
            
            Text("Assistente per esame orale")
                .font(.title2)
            
            VStack(spacing: 6) {
                Text(Configuration.model)
                    .font(.body)

                switch viewModel.gptValidationStatus {
                case .checking:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Verifica del modello")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                case .valid:
                    Label(
                        "Modello disponibile",
                        systemImage: "checkmark.circle"
                    )
                    .foregroundStyle(.green)

                case .missingAPIKey:
                    Text(
                        "Key assente o non valida in Configuration"
                    )
                    .foregroundStyle(.red)

                case .invalidCredentials:
                    Text(
                        "OpenAI ha rifiutato la key: credenziali non valide o scadute"
                    )
                    .foregroundStyle(.red)

                case .insufficientPermissions:
                    Text(
                        "La key non dispone dei permessi necessari"
                    )
                    .foregroundStyle(.red)

                case .modelUnavailable:
                    Text(
                        "Modello non disponibile o non accessibile"
                    )
                    .foregroundStyle(.red)

                case .unavailable:
                    Text(
                        "Impossibile verificare il modello. Controlla la connessione."
                    )
                    .foregroundStyle(.red)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Text("Istruzioni")
                .font(.headline)
                .padding(.top, 8)
            
            VStack(spacing: 12) {
                Text("Registra la tua domanda. Attendi la risposta, che verrà mostrata e letta ad alta voce.")
                Text("Durante la risposta, usa il doppio tap nel riquadro in basso per fare una domanda breve.")
            }
            .font(.body)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Trascrizione
    
    private var transcriptTextForDisplay: String {
        let text = viewModel.shortExchangeText.isEmpty
        ? speechManager.transcript
        : viewModel.shortExchangeText
        
        let instruction: String?
        
        switch viewModel.appState {
        case .responding where viewModel.shouldShowMainPlaybackPrompt:
            instruction = viewModel.isMainSpeechPaused
            ? "▶️ Tap qui per riprendere"
            : "⏸️ Tap qui per mettere in pausa"
            
        case .shortResponding
            where !viewModel.isGeneratingShortResponse:
            instruction = viewModel.isShortSpeechPaused
            ? "▶️ Tap qui per riprendere"
            : "⏸️ Tap qui per mettere in pausa"
            
        default:
            instruction = nil
        }
        
        guard let instruction else {
            return text
        }
        
        return text.isEmpty
        ? instruction
        : "\(instruction)\n\n\(text)"
    }
    
    private var transcriptArea: some View {
        ScrollView {
            Text(transcriptTextForDisplay)
                .font(.system(size: 14))
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .textSelection(.disabled)
                .padding(8)
        }
        .frame(minHeight: 100, maxHeight: 150)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.3))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.togglePauseSpeaking()
        }
    }
    
    // MARK: - Risposta
    
    private var responseArea: some View {
        ScrollView {
            Text(highlightedResponseText)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .textSelection(.enabled)
                .padding(12)
        }
        .frame(maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.secondary.opacity(0.2))
        )
    }
    
    private var responseTextForDisplay: String {
        viewModel.responseText.isEmpty
        ? "La risposta apparirà qui."
        : viewModel.responseText
    }
    
    private var highlightedResponseText: AttributedString {
        var text = AttributedString(responseTextForDisplay)
        text.font = .system(size: 14)
        
        let sentence = speechManager.currentMainSentence
        
        guard !sentence.isEmpty,
              let range = text.range(of: sentence) else {
            return text
        }
        
        text[range].font = .system(size: 14, weight: .bold)
        text[range].backgroundColor = Color.yellow.opacity(0.3)
        
        return text
    }
    
    // MARK: - Stato
    
    private var statusArea: some View {
        HStack(spacing: 8) {
            if viewModel.isMainSpeechPaused ||
                viewModel.isShortSpeechPaused {
                Image(systemName: "pause.fill")
                
            } else if viewModel.isPreparingRecording ||
                        viewModel.isGeneratingMainResponse ||
                        viewModel.isGeneratingShortResponse {
                ProgressView()
                    .tint(.primary)
                
            } else {
                switch viewModel.appState {
                case .recording, .shortRecording:
                    Image(systemName: "mic.fill")
                    
                case .responding
                    where !viewModel.isGeneratingMainResponse,
                        .shortResponding
                    where !viewModel.isGeneratingShortResponse:
                    Image(systemName: "speaker.wave.2.fill")
                    
                default:
                    EmptyView()
                }
            }
            
            if viewModel.appState != .idle || viewModel.gptValidationStatus == .valid {
                Text(viewModel.currentStatus)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Pulsante principale
    
    private var mainButtonArea: some View {
        Button(action: viewModel.buttonTapped) {
            Label(
                viewModel.buttonLabel,
                systemImage:
                    viewModel.appState == .recording ||
                viewModel.appState == .shortRecording
                ? "stop.fill"
                : "mic.fill"
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isMainButtonDisabled)
    }
    
    // MARK: - Area dei tocchi
    
    private var bottomTapArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.10))
            
            statusArea
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )
                .padding(.top, 8)
            
            if !viewModel.showInitialInstructions {
                VStack(spacing: 4) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 24))
                    
                    Text(viewModel.tapAreaTitle)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .padding(10)
                }
                .foregroundColor(.accentColor)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .center
                )
                .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .contentShape(Rectangle())
        .gesture(
            ExclusiveGesture(
                TapGesture(count: 2),
                TapGesture(count: 1)
            )
            .onEnded { value in
                guard !viewModel.showInitialInstructions else {
                    return
                }
                
                switch value {
                case .first:
                    viewModel.handleDoubleTap()
                    
                case .second:
                    viewModel.handleSingleTap()
                }
            }
        )
    }
}
