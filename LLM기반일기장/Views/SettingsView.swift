import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var diaryStore: DiaryStore
    @EnvironmentObject var llmService: LLMService
    @EnvironmentObject var authManager: BiometricAuthManager
    @EnvironmentObject var ttsService: TTSService
    
    @State private var showClearConfirm = false
    @State private var isTestingConnection = false
    @State private var testResultMessage: String? = nil
    @State private var isTestSuccess: Bool = false
    
    var body: some View {
        Form {
            // MARK: - 1. Gemini AI 모델 및 API 연동 설정
            Section(header: Text("Gemini AI API & 모델 설정").font(.headline)) {
                // Connection Mode Indicator
                HStack {
                    Text("현재 동작 모드:")
                        .font(.subheadline)
                    Spacer()
                    if llmService.useSimulation {
                        Text("로컬 시뮬레이션 모드")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(6)
                    } else {
                        Text("실제 Google Gemini API 연동")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(6)
                    }
                }
                
                Toggle("로컬 시뮬레이션 모드 강제 사용", isOn: $llmService.useSimulation)
                    .tint(.accentColor)
                
                Text("시뮬레이션 모드가 켜져 있으면 API 키 없이도 로컬 룰 엔진으로 일기 대화 및 감정 분석을 테스트할 수 있습니다. 실제 Gemini API를 호출하려면 이 스위치를 끄고 API 키를 입력하세요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                // API Key Input
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Google Gemini API Key")
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                        Spacer()
                        if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                            Link(destination: url) {
                                HStack(spacing: 2) {
                                    Text("API 키 무료 발급 (Google AI Studio)")
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            }
                        }
                    }
                    
                    HStack(spacing: 8) {
                        SecureField("API 키 입력 (AIzaSy...)", text: $llmService.apiKey)
                            .textFieldStyle(.roundedBorder)
                        
                        Button(action: {
                            runApiTest()
                        }) {
                            HStack(spacing: 4) {
                                if isTestingConnection {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "bolt.fill")
                                }
                                Text("연동 테스트")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isTestingConnection)
                    }
                }
                
                // Test result message banner
                if let testMsg = testResultMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: isTestSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(isTestSuccess ? .green : .red)
                            .font(.title3)
                        Text(testMsg)
                            .font(.caption)
                            .foregroundColor(isTestSuccess ? .green : .red)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(8)
                    .background(isTestSuccess ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Gemini Model Selector
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("대화 및 분석용 Gemini 모델")
                            .font(.subheadline.bold())
                        Spacer()
                        Button(action: {
                            Task {
                                await llmService.fetchAvailableModels()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("모델 목록 새로고침")
                            }
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(llmService.isLoadingModels)
                    }
                    
                    if llmService.isLoadingModels {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Gemini API 모델 목록 조회 중...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Picker("Gemini 모델 선택", selection: $llmService.selectedModel) {
                            ForEach(llmService.availableModels) { model in
                                Text(model.displayName)
                                    .tag(model.cleanId)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        if let activeModelInfo = llmService.availableModels.first(where: { $0.cleanId == llmService.selectedModel || $0.id == llmService.selectedModel }) {
                            Text(activeModelInfo.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    
                    if let err = llmService.fetchModelsError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.top, 4)
            }
            
            // MARK: - 2. AI 음성 대화 (TTS - Text To Speech) 설정
            Section(header: Text("🔊 AI 음성 대화 (TTS) 설정").font(.headline)) {
                Toggle("AI 목소리 답변 (TTS) 사용", isOn: $ttsService.isTTSEnabled)
                    .tint(.accentColor)
                
                if ttsService.isTTSEnabled {
                    Toggle("AI 답변 생성 완료 시 자동 음성 읽기", isOn: $ttsService.autoReadAIResponse)
                        .tint(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("음성 속도")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.2fx", ttsService.ttsRate * 2.0))
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                        }
                        Slider(value: $ttsService.ttsRate, in: 0.2...0.75, step: 0.05)
                    }
                    
                    let voices = TTSService.getAvailableKoreanVoices()
                    if !voices.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("한국어 목소리 선택", selection: $ttsService.selectedVoiceIdentifier) {
                                ForEach(voices, id: \.identifier) { voice in
                                    Text("\(voice.name) (\(voice.qualityDescription))")
                                        .tag(voice.identifier)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            Text("💡 안내: Siri 전용 음성은 Apple 보안 정책상 일반 개발자 앱 접근이 제한됩니다. 고품질/프리미엄 목소리를 사용하시려면 [시스템 설정 > 손쉬운 사용 > 말하기 콘텐츠 > 음성 > 한국어]에서 다운로드하세요.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                                .padding(.top, 2)
                        }
                    }
                    
                    Button(action: {
                        if ttsService.isSpeaking {
                            ttsService.stop()
                        } else {
                            ttsService.speak(text: "안녕하세요! 오늘 당신의 하루를 따뜻하게 들어드릴 AI 일기 비서입니다.")
                        }
                    }) {
                        HStack {
                            Image(systemName: ttsService.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                            Text(ttsService.isSpeaking ? "음성 테스트 정지" : "🔊 목소리 샘플 들어보기")
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // MARK: - 3. 데이터 관리
            Section(header: Text("데이터 관리").font(.headline)) {
                Button(action: {
                    diaryStore.loadMockDataIfEmpty()
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down.on.square")
                        Text("데모 데이터 로드 (일기장 비어있을 때)")
                    }
                }
                .foregroundColor(.accentColor)
                
                Button(role: .destructive, action: {
                    showClearConfirm = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("모든 일기 데이터 초기화")
                    }
                }
                .foregroundColor(.red)
                .alert("일기 초기화", isPresented: $showClearConfirm) {
                    Button("취소", role: .cancel) { }
                    Button("삭제", role: .destructive) {
                        diaryStore.clearAll()
                    }
                } message: {
                    Text("저장된 모든 일기 내용과 분석 데이터가 영구적으로 삭제됩니다. 계속하시겠습니까?")
                }
            }
            
            // MARK: - 3. 보안 및 앱 설정
            Section(header: Text("보안 및 앱 설정").font(.headline)) {
                HStack {
                    Image(systemName: "touchid")
                        .foregroundColor(.secondary)
                    Text("생체 인증 지원 상태")
                    Spacer()
                    Text(authManager.isBiometricsAvailable ? "지원됨" : "지원 안 됨")
                        .foregroundColor(authManager.isBiometricsAvailable ? .green : .secondary)
                }
                
                Button(action: {
                    authManager.logout()
                }) {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("일기장 수동 잠그기 (로그아웃)")
                    }
                }
                .foregroundColor(.orange)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("설정")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    private func runApiTest() {
        isTestingConnection = true
        testResultMessage = nil
        
        Task {
            let result = await llmService.testApiConnection()
            await MainActor.run {
                self.isTestingConnection = false
                self.isTestSuccess = result.success
                self.testResultMessage = result.message
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DiaryStore())
        .environmentObject(LLMService())
        .environmentObject(BiometricAuthManager())
}
