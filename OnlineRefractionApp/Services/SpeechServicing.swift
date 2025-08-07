//
//  SpeechServicing.swift
//  OnlineRefractionApp
//
//  Created by dionysus on 2025/8/4.
//


import Foundation
import AVFoundation
import Combine

protocol SpeechServicing {
    func speak(_ text: String)
    func stop()
    /// 停→稍等→播，避免页面切换时首句被吞
    func restartSpeak(_ text: String, delay: TimeInterval)
}

final class SpeechService: NSObject, SpeechServicing {
    private let syn = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        syn.delegate = nil
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    func speak(_ text: String) {
        DispatchQueue.main.async {
            try? self.session.setActive(true)
            let u = AVSpeechUtterance(string: text)
            u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            u.rate  = AVSpeechUtteranceDefaultSpeechRate * 0.95
            u.postUtteranceDelay = 0.05
            self.syn.speak(u)
        }
    }

    func stop() {
        syn.stopSpeaking(at: .immediate)
    }

    func restartSpeak(_ text: String, delay: TimeInterval = 0.15) {
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
