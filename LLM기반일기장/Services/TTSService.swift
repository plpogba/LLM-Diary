import Foundation
import AVFoundation
import Combine

class TTSService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking: Bool = false
    @Published var currentlySpeakingText: String = ""
    
    @Published var isTTSEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTTSEnabled, forKey: "tts_enabled")
        }
    }
    
    @Published var autoReadAIResponse: Bool {
        didSet {
            UserDefaults.standard.set(autoReadAIResponse, forKey: "tts_auto_read")
        }
    }
    
    @Published var ttsRate: Float {
        didSet {
            UserDefaults.standard.set(ttsRate, forKey: "tts_rate")
        }
    }
    
    @Published var selectedVoiceIdentifier: String {
        didSet {
            UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "tts_voice_identifier")
        }
    }
    
    private let synthesizer = AVSpeechSynthesizer()
    private var completionHandler: (() -> Void)?
    
    var onSpeechStarted: (() -> Void)?
    var onSpeechFinished: (() -> Void)?
    
    override init() {
        self.isTTSEnabled = UserDefaults.standard.object(forKey: "tts_enabled") as? Bool ?? true
        self.autoReadAIResponse = UserDefaults.standard.object(forKey: "tts_auto_read") as? Bool ?? true
        self.ttsRate = UserDefaults.standard.object(forKey: "tts_rate") as? Float ?? AVSpeechUtteranceDefaultSpeechRate
        
        // 초기화 시점 결정: 저장된 값이 없거나, 저장된 식별자가 실제 기기에 없거나, 기본 품질인 경우 최고품질 보이스로 강제 갱신
        let savedIdentifier = UserDefaults.standard.string(forKey: "tts_voice_identifier") ?? ""
        let availableVoices = TTSService.getAvailableKoreanVoices()
        
        let bestVoice = availableVoices.first
        let savedVoiceExists = availableVoices.contains(where: { $0.identifier == savedIdentifier })
        
        if savedIdentifier.isEmpty || !savedVoiceExists {
            self.selectedVoiceIdentifier = bestVoice?.identifier ?? ""
        } else {
            // 사용자가 수동으로 선택한 게 아니라면 최고 품질 보이스로 강제 업그레이드 시도
            self.selectedVoiceIdentifier = bestVoice?.identifier ?? savedIdentifier
        }
        
        super.init()
        synthesizer.delegate = self
        
        // 디버깅용 로그: 현재 적용된 보이스 이름과 품질 확인
        if let currentVoice = AVSpeechSynthesisVoice(identifier: self.selectedVoiceIdentifier) {
            print("🔊 [TTSService] 최종 선택된 보이스: \(currentVoice.name) | 품질: \(currentVoice.qualityDescription)")
        }
    }
    
    static func getAvailableKoreanVoices() -> [AVSpeechSynthesisVoice] {
        let koreanVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ko") }
        
        // 다운로드한 Premium > Enhanced > Default 순서로 우선 정렬
        return koreanVoices.sorted { voice1, voice2 in
            if voice1.quality.rawValue != voice2.quality.rawValue {
                return voice1.quality.rawValue > voice2.quality.rawValue
            }
            return voice1.name < voice2.name
        }
    }
    
    func speak(text: String, completion: (() -> Void)? = nil) {
        guard isTTSEnabled else {
            completion?()
            return
        }
        
        let cleanedText = cleanTextForSpeech(text)
        guard !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion?()
            return
        }
        
        stop()
        
        self.completionHandler = completion
        self.currentlySpeakingText = cleanedText
        self.isSpeaking = true
        
        DispatchQueue.main.async {
            self.onSpeechStarted?()
        }
        
        let utterance = AVSpeechUtterance(string: cleanedText)
        let effectiveRate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, ttsRate))
        utterance.rate = effectiveRate
        utterance.pitchMultiplier = 1.0
        
        // 최우선 순위: 선택된 식별자, 없으면 가용 최고 품질 보이스, 마지막 폴백
        if !selectedVoiceIdentifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            utterance.voice = voice
        } else if let bestVoice = TTSService.getAvailableKoreanVoices().first {
            utterance.voice = bestVoice
        } else if let fallbackVoice = AVSpeechSynthesisVoice(language: "ko-KR") {
            utterance.voice = fallbackVoice
        }
        
        synthesizer.speak(utterance)
    }
    
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.currentlySpeakingText = ""
        }
    }
    
    func togglePlayback(for text: String) {
        let cleaned = cleanTextForSpeech(text)
        if isSpeaking && currentlySpeakingText == cleaned {
            stop()
        } else {
            speak(text: text)
        }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
            self.onSpeechStarted?()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.currentlySpeakingText = ""
            let handler = self.completionHandler
            self.completionHandler = nil
            handler?()
            self.onSpeechFinished?()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.currentlySpeakingText = ""
            let handler = self.completionHandler
            self.completionHandler = nil
            handler?()
            self.onSpeechFinished?()
        }
    }
    
    // MARK: - Text Cleaning Helper
    private func cleanTextForSpeech(_ text: String) -> String {
        var clean = text
        clean = clean.replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "\\*", with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "#+", with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "`", with: "")
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension AVSpeechSynthesisVoice {
    var qualityDescription: String {
        switch self.quality {
        case .premium:
            return "프리미엄 (최고품질)"
        case .enhanced:
            return "향상됨 (고품질)"
        default:
            return "기본"
        }
    }
}