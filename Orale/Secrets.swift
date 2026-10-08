//  Secrets.swift

import Foundation

enum Secrets {
    static var openAIKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OpenAI_API_Key") as? String,
              !key.isEmpty else {
            fatalError("OpenAI_API_Key mancante in Info.plist")
        }
        return key
    }
}
