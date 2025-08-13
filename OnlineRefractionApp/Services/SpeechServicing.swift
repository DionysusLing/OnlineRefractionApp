import Foundation
import AVFoundation   // ✅ 新增

protocol SpeechServicing {
    func speak(_ text: String)
    func restartSpeak(_ text: String, delay: TimeInterval)
    func stop()
}

final class SpeechService: ObservableObject, SpeechServicing {

    private let session = AVAudioSession.sharedInstance()

    init() {
        configureAudioSessionForceSpeak()
        observeInterruptions()
    }

    /// 在静音开关打开时也能播报
    private func configureAudioSessionForceSpeak() {
        do {
            // .playback 绕过静音拨片；.spokenAudio 优化 TTS；.duckOthers 轻压低其他音频
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            print("Audio session config error: \(error)")
        }
    }

    /// 有时被系统打断后需要重新激活
    private func reactivateIfNeeded() {
        do { try session.setActive(true, options: []) } catch { }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] n in
            guard let info = n.userInfo,
                  let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }

            switch type {
            case .ended:
                self?.reactivateIfNeeded()   // 来电等中断结束后恢复会话
            default:
                break
            }
        }
    }

    
    protocol SpeechServicing {
        func speak(_ text: String)
        func stop()
        func restartSpeak(_ text: String, delay: TimeInterval)
        func cancelPending()
    }

    final class SpeechService: SpeechServicing {
        private var pending: DispatchWorkItem?

        func restartSpeak(_ text: String, delay: TimeInterval = 0) {
            cancelPending()
            stop()
            let work = DispatchWorkItem { [weak self] in self?.speak(text) }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        func cancelPending() {
            pending?.cancel(); pending = nil
        }

        func stop() {
            // 停止当前 TTS
        }

        func speak(_ text: String) {
            // 播报实现
        }
    }

    // MARK: - API

    func speak(_ text: String) {
        reactivateIfNeeded()
        SpeechDelegate.shared.speak(text)
    }

    func restartSpeak(_ text: String, delay: TimeInterval = 0.05) {
        reactivateIfNeeded()
        SpeechDelegate.shared.restartSpeak(text, delay: delay)
    }

    func stop() {
        SpeechDelegate.shared.stop()
    }
}
