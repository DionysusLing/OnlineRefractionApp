import Foundation

protocol SpeechServicing {
    func speak(_ text: String)
    func restartSpeak(_ text: String, delay: TimeInterval)
    func stop()
}

final class SpeechService: ObservableObject, SpeechServicing {
    func speak(_ text: String) {
        SpeechDelegate.shared.speak(text)
    }
    func restartSpeak(_ text: String, delay: TimeInterval = 0.05) {
        SpeechDelegate.shared.restartSpeak(text, delay: delay)
    }
    func stop() {
        SpeechDelegate.shared.stop()
    }
}
