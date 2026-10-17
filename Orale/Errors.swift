// Errors.swift

import Foundation

// MARK: - Stato di verifica del provider

enum ProviderValidationStatus: Equatable, Sendable {
    case checking
    case valid
    case missingAPIKey
    case invalidCredentials
    case insufficientPermissions
    case modelUnavailable
    case unavailable
}

// MARK: - Errori del servizio GPT

enum GPTServiceError: LocalizedError {
    case missingAPIKey
    case http(statusCode: Int, message: String)
    case responseFailed(String)
    case responseIncomplete(String)
    case connectionEndedPrematurely

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Chiave API assente"

        case .http(let statusCode, let message):
            let details = message.isEmpty ? "" : " \(message)"

            switch statusCode {
            case 401:
                return "Chiave API non valida o scaduta (HTTP 401)\(details)"

            case 403:
                return "Permessi insufficienti per questo servizio o modello (HTTP 403)\(details)"

            case 404:
                return "Modello non disponibile (HTTP 404)\(details)"

            default:
                return "Richiesta fallita (HTTP \(statusCode))\(details)"
            }

        case .responseFailed(let message):
            return "Generazione fallita: \(message)"

        case .responseIncomplete(let reason):
            return "Risposta incompleta: \(reason)"

        case .connectionEndedPrematurely:
            return "Connessione terminata prima del completamento della risposta"
        }
    }
}

// MARK: - Classificazione e diagnostica

enum AppErrorHandler {

    /// Classifica l'errore quando ci sono informazioni sufficienti.
    static func validationStatus(
        for error: Error,
        duringInitialCheck: Bool = false
    ) -> ProviderValidationStatus? {

        guard let serviceError = error as? GPTServiceError else {
            return nil
        }

        switch serviceError {
        case .missingAPIKey:
            return .missingAPIKey

        case .http(let statusCode, _):
            switch statusCode {
            case 401:
                return .invalidCredentials

            case 403:
                return .insufficientPermissions

            case 404:
                return .modelUnavailable

            case 400 where duringInitialCheck:
                return .modelUnavailable

            default:
                return nil
            }

        case .responseFailed,
             .responseIncomplete,
             .connectionEndedPrematurely:
            return nil
        }
    }

    /// Registra un errore tecnico
    static func log(
        _ error: Error,
        context: String = "Errore"
    ) {
        let nsError = error as NSError
        print("[ERRORE] \(context): \(error.localizedDescription) [\(String(reflecting: type(of: error))) | \(nsError.domain):\(nsError.code)]")
    }

    /// Registra un messaggio senza dover creare un oggetto Error.
    static func log(
        _ message: String,
        context: String = "Errore"
    ) {
        print("[ERRORE] \(context): \(message)")
    }
}
