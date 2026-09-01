import Foundation
import Speech
import AVFoundation
import Combine

class SpeechRecognizer: ObservableObject {
    enum PermissionStatus {
        case undetermined
        case authorized
        case denied
    }
    
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var permissionStatus: PermissionStatus = .undetermined
    @Published var errorMessage: String? = nil
    @Published var isSilenceDetected: Bool = false
    @Published var isPausedForTTS: Bool = false
    
    var onSilenceDetected: ((String) -> Void)?
    var silenceThreshold: TimeInterval = 1.6 // Seconds of silence to trigger auto-send
    var autoRestart: Bool = true // Auto-restart mic after silence send
    
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    
    private var localeIdentifier: String
    
    init(localeIdentifier: String = "ko-KR") {
        self.localeIdentifier = localeIdentifier
    }
    
    func checkPermissions() {
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        }
        
        let speechAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let micAuthorized = micStatus == .authorized
        
        DispatchQueue.main.async {
            if speechAuthorized && micAuthorized {
                self.permissionStatus = .authorized
            } else if SFSpeechRecognizer.authorizationStatus() == .denied || micStatus == .denied {
                self.permissionStatus = .denied
            } else {
                self.permissionStatus = .undetermined
            }
        }
    }
    
    func requestPermissions() {
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        }
        
        SFSpeechRecognizer.requestAuthorization { authStatus in
            AVCaptureDevice.requestAccess(for: .audio) { micGranted in
                DispatchQueue.main.async {
                    if authStatus == .authorized && micGranted {
                        self.permissionStatus = .authorized
                        self.errorMessage = nil
                        self.startRecording()
                    } else {
                        self.permissionStatus = .denied
                        self.errorMessage = "음성 인식 및 마이크 사용 권한이 거부되었습니다. 설정에서 권한을 확인해주세요."
                    }
                }
            }
        }
    }
    
    func pauseForTTS() {
        DispatchQueue.main.async {
            self.isPausedForTTS = true
            self.transcript = ""
            self.stopRecording()
        }
    }
    
    func resumeFromTTS(delay: TimeInterval = 0.6) {
        DispatchQueue.main.async {
            self.isPausedForTTS = false
            self.transcript = ""
            if self.autoRestart {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    if !self.isPausedForTTS && !self.isRecording {
                        self.startRecording()
                    }
                }
            }
        }
    }
    
    func startRecording() {
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        }
        
        guard permissionStatus == .authorized else {
            requestPermissions()
            return
        }
        
        guard !isRecording && !isPausedForTTS else { return }
        
        // Invalidate silence timer
        silenceTimer?.invalidate()
        silenceTimer = nil
        isSilenceDetected = false
        
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        errorMessage = nil
        transcript = ""
        
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.errorMessage = "오디오 세션을 설정할 수 없습니다: \(error.localizedDescription)"
            return
        }
        #endif
        
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        self.recognitionRequest = recognitionRequest
        recognitionRequest.shouldReportPartialResults = true
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            self.errorMessage = "음성 인식 서비스를 현재 사용할 수 없습니다."
            return
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            if !self.isPausedForTTS {
                recognitionRequest.append(buffer)
            }
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            self.errorMessage = "오디오 엔진을 시작할 수 없습니다: \(error.localizedDescription)"
            inputNode.removeTap(onBus: 0)
            return
        }
        
        isRecording = true
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            guard !self.isPausedForTTS else { return }
            var isFinal = false
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    if !self.isPausedForTTS {
                        self.transcript = text
                        self.resetSilenceTimer()
                    }
                }
                isFinal = result.isFinal
            }
            
            if error != nil || isFinal {
                if let error = error {
                    print("Speech recognition error: \(error.localizedDescription)")
                }
                self.stopRecording()
            }
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && isRecording && !isPausedForTTS else { return }
        
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            guard let self = self, self.isRecording, !self.isPausedForTTS else { return }
            DispatchQueue.main.async {
                self.isSilenceDetected = true
                let finalText = self.transcript
                self.stopRecording()
                self.onSilenceDetected?(finalText)
                // Auto-restart mic for always-on listening
                if self.autoRestart && !self.isPausedForTTS {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isSilenceDetected = false
                        if !self.isPausedForTTS {
                            self.startRecording()
                        }
                    }
                }
            }
        }
    }
    
    func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        guard isRecording else { return }
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.ambient, mode: .default)
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            self.audioEngine = nil
            self.recognitionRequest = nil
            self.recognitionTask = nil
        }
    }
}
