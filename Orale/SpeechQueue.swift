// SpeechQueue.swift

import Foundation

final class SpeechQueue {
    
    struct Item {
        let text: String
        let rate: Float
        let onFinished: (() -> Void)?
    }
    
    private(set) var items: [Item] = []
    private(set) var currentItem: Item?
    private(set) var isPaused = false
    
    var isEmpty: Bool {
        items.isEmpty && currentItem == nil
    }
    
    func enqueue(
        text: String,
        rate: Float,
        onFinished: (() -> Void)? = nil
    ) {
        items.append(
            Item(
                text: text,
                rate: rate,
                onFinished: onFinished
            )
        )
    }
    
    func next() -> Item? {
        guard currentItem == nil else {
            return nil
        }
        
        guard !items.isEmpty else {
            return nil
        }
        
        currentItem = items.removeFirst()
        return currentItem
    }
    
    func finishCurrent() {
        currentItem?.onFinished?()
        currentItem = nil
    }
    
    func pause() {
        isPaused = true
    }
    
    func resume() {
        isPaused = false
    }
    
    func clear() {
        items.removeAll()
        currentItem = nil
        isPaused = false
    }
}
