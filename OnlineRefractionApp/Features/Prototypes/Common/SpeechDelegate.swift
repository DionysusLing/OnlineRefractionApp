// Services/SpeechDelegate.swift
import AVFoundation

/// 全局语音助手（单例）。
/// Swift 6 下保持非 actor，用 @unchecked Sendable 表示仅在主线程使用。
final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechDelegate()

    /// 打开后如果“没声音”，请看控制台 log
    private let enableLogging = true

    private let synthesizer: AVSpeechSynthesizer
    private let audioSession = AVAudioSession.sharedInstance()

    private var onFinish: (() -> Void)?
    private var fallbackTimer: Timer?

    private override init() {
        self.synthesizer = AVSpeechSynthesizer()
        super.init()
        self.synthesizer.delegate = self
    }

    // MARK: - Public API

    /// 直接说一段话（会打断当前播报）
    func speak(_ text: String, completion: @escaping () -> Void = {}) {
        stopInternal(invokeFinish: false) // 先打断上一次，但不回调上一次完成

        // 激活音频会话：播报类语音，压低其他音频（不完全打断）
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true, options: [])
        } catch {
            if enableLogging { print("[SpeechDelegate] audio session error:", error) }
        }

        // 捕获回调 & 启动兜底计时（某些设备上 didFinish 偶发不回调）
        onFinish = completion
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.enableLogging { print("[SpeechDelegate] fallback finish fired") }
            self.finishAndDeactivate()
        }

        // 构造语音
        let utt = AVSpeechUtterance(string: text)
        utt.rate = AVSpeechUtteranceDefaultSpeechRate
        // 语言：优先系统首选（完整 BCP-47），fallback zh-CN
        let preferred = Locale.preferredLanguages.first ?? "zh-CN"
        utt.voice = AVSpeechSynthesisVoice(language: preferred)

        if enableLogging { print("[SpeechDelegate] speak →", text) }
        synthesizer.speak(utt)
    }

    /// 停止当前播报后，稍等再播新文案（页面切换时建议用这个）
    func restartSpeak(_ text: String, delay: TimeInterval = 0.05) {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.speak(text)
        }
    }

    /// 立即停止（离开页面时务必调用）
    func stop() {
        stopInternal(invokeFinish: false)
    }

    // MARK: - Private

    private func stopInternal(invokeFinish: Bool) {
        fallbackTimer?.invalidate()
        fallbackTimer = nil

        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        if invokeFinish {
            finishAndDeactivate()
        } else {
            // 仅停播，不触发完成回调
            onFinish = nil
            deactivateAudioSession()
        }
    }

    private func finishAndDeactivate() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil

        let done = onFinish
        onFinish = nil
        deactivateAudioSession()
        DispatchQueue.main.async { done?() }
    }

    private func deactivateAudioSession() {
        do {
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            if enableLogging { print("[SpeechDelegate] deactivate error:", error) }
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didStart utterance: AVSpeechUtterance) {
        if enableLogging { print("[SpeechDelegate] didStart") }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        if enableLogging { print("[SpeechDelegate] didFinish") }
        finishAndDeactivate()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        if enableLogging { print("[SpeechDelegate] didCancel") }
        // 被 stop 打断：不当作完成，仅清理资源
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        onFinish = nil
        deactivateAudioSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didPause utterance: AVSpeechUtterance) {
        if enableLogging { print("[SpeechDelegate] didPause") }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didContinue utterance: AVSpeechUtterance) {
        if enableLogging { print("[SpeechDelegate] didContinue") }
    }
}

/// AVSpeechSynthesizer 不是 Sendable；我们保证只在主线程使用它。
extension SpeechDelegate: @unchecked Sendable {}
