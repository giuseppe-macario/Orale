// SpeechQueue.swift

final class SpeechQueue {
    
    struct Item {
        let text: String
        let rate: Float
        let onFinished: (() -> Void)?
    }
    
    private var queuedItems: [Item] = []
    private var activeItem: Item?
    private var paused = false
    
    var currentItem: Item? {
        activeItem
    }
    
    var isPaused: Bool {
        paused
    }
    
    var isEmpty: Bool {
        queuedItems.isEmpty && activeItem == nil
    }
    
    func enqueue(
        text: String,
        rate: Float,
        onFinished: (() -> Void)? = nil
    ) {
        queuedItems.append(
            Item(
                text: text,
                rate: rate,
                onFinished: onFinished
            )
        )
    }
    
    func next() -> Item? {
        guard activeItem == nil else {
            return nil
        }
        
        guard !queuedItems.isEmpty else {
            return nil
        }
        
        let item = queuedItems.removeFirst()
        activeItem = item
        
        return item
    }
    
    func finishCurrent() {
        activeItem?.onFinished?()
        activeItem = nil
    }
    
    func pause() {
        paused = true
    }
    
    func resume() {
        paused = false
    }
    
    func clear() {
        queuedItems.removeAll()
        activeItem = nil
        paused = false
    }
}
