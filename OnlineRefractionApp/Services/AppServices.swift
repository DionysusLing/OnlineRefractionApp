import Foundation
import AVFoundation
import Combine

protocol SpeechServicing {
    func speak(_ text: String)
    func stop()
}

final class SpeechService: SpeechServicing {
    private let syn = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()

    init() {
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    func speak(_ text: String) {
        // 不再立即 stop，避免把刚开始的播报打断
        DispatchQueue.main.async {
            try? self.session.setActive(true)
            let u = AVSpeechUtterance(string: text)
            u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            u.rate  = AVSpeechUtteranceDefaultSpeechRate * 0.95
            u.postUtteranceDelay = 0.05
            self.syn.speak(u)
        }
    }

    func stop() { syn.stopSpeaking(at: .immediate) }
}

extension SpeechServicing {
    /// 停止当前播报，并在 delay 后开始新的播报（避免页面切换时序打架）
    func restartSpeak(_ text: String, delay: TimeInterval = 0.18) {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.speak(text)
        }
    }
}


final class AppServices: ObservableObject {
    let speech: SpeechServicing
    init(speech: SpeechServicing = SpeechService()) { self.speech = speech }
}


// 放在文件任意位置（不改你已有的 SpeechService）这部分是新增的0804 20:41为解决散光语音不播的
extension SpeechServicing {
    func speak(_ text: String, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.speak(text)
        }
    }
}
