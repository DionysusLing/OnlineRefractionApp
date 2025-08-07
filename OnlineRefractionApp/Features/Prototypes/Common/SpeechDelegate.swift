// SpeechDelegate.swift
import AVFoundation

/// 全局语音助手。单例。兼容 Swift 6 delegate 要求（非 actor 版，用 @unchecked Sendable 信任主线程使用）。
final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechDelegate()

    /// 打开以后如果“没声音”请看控制台 log
    private let enableLogging = true

    private let synthesizer: AVSpeechSynthesizer
    private var onFinish: (() -> Void)?
    private let audioSession = AVAudioSession.sharedInstance()
    private var fallbackTimer: Timer?

    private override init() {
        self.synthesizer = AVSpeechSynthesizer()
        super.init()
        self.synthesizer.delegate = self
    }

    /// 播报文字，播报完/取消后回调一次
    func speak(_ text: String, completion: @escaping () -> Void) {
        if enableLogging { print("[SpeechDelegate] speak requested: '\(text)'") }

        // 配置音频会话（尽量确保能听到：播放类别 + 强制扬声器）
        do {
            try audioSession.setCategory(.playback, options: [.duckOthers])
            // 强制走扬声器（避免在某些 route 下被静默到听筒）
            try audioSession.overrideOutputAudioPort(.speaker)
            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
            if enableLogging {
                print("[SpeechDelegate] audio session active. Category: \(audioSession.category.rawValue), Mode: \(audioSession.mode.rawValue)")
                print("[SpeechDelegate] current route: \(audioSession.currentRoute.outputs.map { $0.portType.rawValue })")
            }
        } catch {
            if enableLogging {
                print("[SpeechDelegate] audio session configuration failed: \(error)")
            }
        }

        // 捕获回调并设置
        onFinish = completion

        // 构造 utterance
        let utt = AVSpeechUtterance(string: text)
        utt.rate = AVSpeechUtteranceDefaultSpeechRate

        // 语言选择：优先系统 preferredLanguages（完整 BCP-47），fallback zh-CN
        let preferred = Locale.preferredLanguages.first ?? "zh-CN"
        utt.voice = AVSpeechSynthesisVoice(language: preferred)
        if enableLogging {
            print("[SpeechDelegate] using voice language: \(preferred)")
        }

        // 启动一个保险：5 秒还没 finish 就 fallback 调用一次避免卡住
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.enableLogging { print("[SpeechDelegate] fallback timeout triggered") }
            let cb = self.onFinish
            self.onFinish = nil
            DispatchQueue.main.async {
                cb?()
            }
        }

        // 在主线程操作 synthesizer（Apple 推荐）
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.synthesizer.isSpeaking {
                if self.enableLogging { print("[SpeechDelegate] was speaking, stopping first") }
                self.synthesizer.stopSpeaking(at: .immediate)
            }
            self.synthesizer.speak(utt)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        if enableLogging { print("[SpeechDelegate] didStart utterance") }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if enableLogging { print("[SpeechDelegate] didFinish utterance") }
        fallbackTimer?.invalidate()
        let callback = onFinish
        onFinish = nil
        DispatchQueue.main.async {
            callback?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if enableLogging { print("[SpeechDelegate] didCancel utterance") }
        fallbackTimer?.invalidate()
        onFinish = nil
    }
}

/// AVSpeechSynthesizer 不是 Sendable，Swift 6 会警告；我们保证只在主线程用它，关闭检查。
extension SpeechDelegate: @unchecked Sendable {}
