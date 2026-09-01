import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct NewDiaryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var diaryStore: DiaryStore
    @EnvironmentObject var llmService: LLMService
    @EnvironmentObject var ttsService: TTSService
    
    @StateObject private var speechRecognizer = SpeechRecognizer()
    
    enum WriteStep {
        case chatting    // Direct AI real-time chat with follow-up questions
        case preview     // Final output, radar chart & keywords
    }
    
    @State private var step: WriteStep = .chatting
    
    // Chat & Incremental Synthesis variables
    @State private var chatHistory: [ChatMessage] = []
    @State private var chatInput: String = ""
    @State private var currentQuestion: String = ""
    @State private var liveDraft: String = ""
    @State private var showLiveDraftPreview = false
    // 상시 마이크 모드 (항상 켜짐)
    
    // Photo attachment variables
    @State private var attachedImages: [NSImage] = []
    @State private var selectedPreviewImage: NSImage? = nil
    @State private var isTargetedForDrop: Bool = false
    
    // Real-Time Streaming Variables
    @State private var isStreaming = false
    @State private var streamingText = ""
    
    // Final Preview variables
    @State private var finalContent: String = ""
    @State private var diaryTitle: String = ""
    @State private var keywords: [String] = []
    @State private var moodEmoji: String = "😌"
    @State private var emotionScores = EmotionScores.empty
    @State private var summary: String = ""
    
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom top bar
            HStack {
                Button("취소") {
                    dismiss()
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(step == .chatting ? "AI 대화형 일기 작성 (실시간 스트리밍)" : "일기 저장 확인")
                    .font(.headline)
                
                Spacer()
                
                if step == .preview && !isLoading && errorMessage == nil {
                    Button("저장") {
                        saveDiary()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("저장") {}
                        .hidden()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Header Step Indicator
            stepIndicator
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if isLoading && !isStreaming {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Gemini AI(\(llmService.selectedModelDisplayName))가 답변을 스트리밍 분석 중...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    Text("오류 발생")
                        .font(.headline)
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("다시 시도") {
                        self.errorMessage = nil
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            } else {
                switch step {
                case .chatting:
                    realtimeChatView
                case .preview:
                    finalPreviewView
                }
            }
        }
        .frame(minWidth: 620, minHeight: 540)
        .onDrop(of: [.image, .fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers: providers)
        }
        .overlay(
            Group {
                if isTargetedForDrop {
                    ZStack {
                        Color.black.opacity(0.4)
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 48))
                                .foregroundColor(.white)
                            Text("사진을 여기에 놓아 일기에 추가하세요")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(32)
                        .background(Color.accentColor.opacity(0.9))
                        .cornerRadius(20)
                        .shadow(radius: 10)
                    }
                    .transition(.opacity)
                }
            }
        )
        .sheet(item: Binding(get: {
            selectedPreviewImage.map { IdentifiableImage(image: $0) }
        }, set: {
            selectedPreviewImage = $0?.image
        })) { item in
            ImageViewerModal(image: item.image) {
                selectedPreviewImage = nil
            }
        }
        .onAppear {
            setupSilenceAutoSend()
            setupTTSCallbacks()
            if chatHistory.isEmpty {
                startInitialConversation()
            }
            // 상시 마이크 자동 시작
            speechRecognizer.autoRestart = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if !ttsService.isSpeaking {
                    speechRecognizer.startRecording()
                }
            }
        }
        .onDisappear {
            ttsService.stop()
            speechRecognizer.autoRestart = false
            speechRecognizer.stopRecording()
        }
        .onChange(of: isStreaming) { streaming in
            if streaming {
                // AI 답변 생성 중엔 마이크 일시 정지
                speechRecognizer.autoRestart = false
                speechRecognizer.stopRecording()
            } else {
                // AI 답변 완료 후 마이크 자동 재개
                speechRecognizer.autoRestart = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !speechRecognizer.isRecording {
                        speechRecognizer.startRecording()
                    }
                }
            }
        }
        .onReceive(speechRecognizer.$transcript) { text in
            if speechRecognizer.isRecording && !text.isEmpty && !ttsService.isSpeaking && !speechRecognizer.isPausedForTTS {
                self.chatInput = text
            }
        }
    }
    
    // MARK: - Subviews
    
    // Step Indicator
    private var stepIndicator: some View {
        HStack(spacing: 20) {
            stepIndicatorNode(stepNum: 1, title: "AI 실시간 대화 (스트리밍)", active: step == .chatting, completed: step == .preview)
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
            stepIndicatorNode(stepNum: 2, title: "감정 분석 & 최종 저장", active: step == .preview, completed: false)
        }
    }
    
    private func stepIndicatorNode(stepNum: Int, title: String, active: Bool, completed: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                if completed {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 24, height: 24)
                    Image(systemName: "check")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .fill(active ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 24, height: 24)
                    Text("\(stepNum)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(active ? .white : .primary)
                }
            }
            Text(title)
                .font(.system(size: 13, weight: active ? .bold : .medium))
                .foregroundColor(active ? .primary : .secondary)
        }
    }
    
    // STEP 1: Direct Real-Time AI Chat View with Streaming
    private var realtimeChatView: some View {
        VStack(spacing: 0) {
            // Model & Live Draft Bar
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                    Text("대화 모델:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(llmService.selectedModelDisplayName)
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .cornerRadius(6)
                    
                    Text("⚡ SSE 스트리밍")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(6)
                    
                    Spacer()
                    
                    // 상시 마이크 상태 표시
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isStreaming ? Color.orange : (speechRecognizer.isRecording ? Color.red : Color.gray))
                            .frame(width: 7, height: 7)
                            .shadow(color: isStreaming ? Color.orange.opacity(0.6) : (speechRecognizer.isRecording ? Color.red.opacity(0.6) : .clear), radius: 4)
                        Text(isStreaming ? "AI 답변 중" : (speechRecognizer.isRecording ? "상시 청취 중" : "마이크 대기"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isStreaming ? .orange : (speechRecognizer.isRecording ? .red : .secondary))
                    }
                    .padding(.trailing, 8)
                    
                    if !liveDraft.isEmpty {
                        Button(action: {
                            withAnimation {
                                showLiveDraftPreview.toggle()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: showLiveDraftPreview ? "chevron.up.square.fill" : "doc.text.fill")
                                Text(showLiveDraftPreview ? "초안 접기" : "실시간 일기 초안")
                            }
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Expandable Live Draft Synthesis Box
                if showLiveDraftPreview && !liveDraft.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("✍️ 실시간 다듬어지는 일기 초안")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("대화에 따라 자동 업데이트됨")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Text(liveDraft)
                            .font(.subheadline)
                            .lineSpacing(4)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.bottom, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Scrollable Chat area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        // History list
                        ForEach(chatHistory) { message in
                            ChatBubble(message: message, modelName: llmService.selectedModelDisplayName)
                                .id(message.id)
                        }
                        
                        // Live SSE Streaming bubble
                        if isStreaming {
                            HStack(alignment: .top, spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.accentColor)
                                        .font(.system(size: 16))
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 4) {
                                        Text("AI 비서 (\(llmService.selectedModelDisplayName))")
                                            .font(.caption.bold())
                                            .foregroundColor(.accentColor)
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    
                                    Text(streamingText.isEmpty ? "답변을 생성 중..." : streamingText)
                                        .font(.body)
                                        .lineSpacing(4)
                                        .padding(14)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(14)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("ai_streaming")
                        }
                        
                        // Current AI question bubble (after streaming complete)
                        if !currentQuestion.isEmpty && !isStreaming {
                            HStack(alignment: .top, spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.accentColor)
                                        .font(.system(size: 16))
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("AI 비서 (\(llmService.selectedModelDisplayName))")
                                            .font(.caption.bold())
                                            .foregroundColor(.accentColor)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            ttsService.togglePlayback(for: currentQuestion)
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: ttsService.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                                                    .font(.system(size: 13))
                                                Text(ttsService.isSpeaking ? "음성 정지" : "다시 듣기")
                                                    .font(.caption)
                                            }
                                            .foregroundColor(.accentColor)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Text(currentQuestion)
                                        .font(.body)
                                        .lineSpacing(4)
                                        .padding(14)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(14)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("ai_question")
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                .onChange(of: chatHistory.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: streamingText) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: currentQuestion) { _ in
                    scrollToBottom(proxy: proxy)
                }
            }
            
            Divider()
            
            // Bottom Input Bar - Always-On Mic
            VStack(spacing: 10) {
                // 항상 보이는 음성 상태 표시 바
                HStack(spacing: 10) {
                    if isStreaming {
                        // AI 답변 중
                        ProgressView()
                            .controlSize(.small)
                        Text("AI가 답변을 생성 중입니다...")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    } else if ttsService.isSpeaking {
                        // AI 음성 낭독 중
                        WaveformView(isRecording: false)
                            .frame(height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("🔊 AI가 목소리로 말씀 드리고 있습니다...")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.accentColor)
                        }
                        Spacer()
                        Button("음성 정지") {
                            ttsService.stop()
                        }
                        .font(.caption.bold())
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if speechRecognizer.isRecording {
                        // 마이크 켜짐 - 말 인식 중
                        WaveformView(isRecording: true)
                            .frame(height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("🎙️ 듣고 있어요 — 말씀이 끝나면 자동으로 전송됩니다")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.red)
                            if !speechRecognizer.transcript.isEmpty {
                                Text(speechRecognizer.transcript)
                                    .font(.subheadline)
                                    .italic()
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                            }
                        }
                    } else {
                        Image(systemName: "mic.slash")
                            .foregroundColor(.secondary)
                        Text("마이크 대기 중...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    // 마이크 수동 정지/재개 버튼
                    Button(action: {
                        if speechRecognizer.isRecording {
                            speechRecognizer.autoRestart = false
                            speechRecognizer.stopRecording()
                        } else {
                            speechRecognizer.autoRestart = true
                            speechRecognizer.startRecording()
                        }
                    }) {
                        Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 16))
                            .foregroundColor(speechRecognizer.isRecording ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStreaming)
                    .help(speechRecognizer.isRecording ? "마이크 끄기" : "마이크 켜기")
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(speechRecognizer.isRecording ? Color.red.opacity(0.05) : Color.clear)
                .cornerRadius(8)
                .padding(.horizontal)
                
                // Attached Photos in Chat View
                if !attachedImages.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("첨부된 사진 (\(attachedImages.count)장)")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        photoThumbnailStrip
                    }
                    .padding(.bottom, 4)
                }
                
                HStack(spacing: 10) {
                    // Add Photo Button
                    Button(action: {
                        ImageFileManager.shared.pickImagesFromPanel { images in
                            self.attachedImages.append(contentsOf: images)
                        }
                    }) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("사진 추가하기 (또는 창으로 드래그 & 드롭)")
                    
                    TextField("직접 입력도 가능합니다...", text: $chatInput)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .disabled(isStreaming)
                        .onSubmit {
                            sendChatMessage()
                        }
                    
                    Button(action: {
                        sendChatMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor((chatInput.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming) ? .gray : .accentColor)
                    }
                    .disabled(chatInput.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                
                // Finalize Button
                Button(action: {
                    finalizeDiaryDirectly()
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("이대로 일기 작성 완료하기 ✨")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.green, Color(red: 0.1, green: 0.6, blue: 0.3)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                    .shadow(color: Color.green.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(isStreaming)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .padding(.top, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }
    
    // STEP 2: Final preview, summary & emotion radar chart
    private var finalPreviewView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Main Header
                VStack(spacing: 8) {
                    Text(moodEmoji)
                        .font(.system(size: 64))
                        .shadow(radius: 4)
                    
                    TextField("일기 제목", text: $diaryTitle)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .padding(.horizontal)
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.accentColor.opacity(0.3))
                                .padding(.horizontal, 40)
                                .offset(y: 16)
                        )
                }
                .padding(.top)
                
                // AI Summary
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundColor(.accentColor)
                        Text("AI 요약 분석")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                    }
                    Text(summary)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineSpacing(4)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.06))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Key Words Tags cloud
                VStack(alignment: .leading, spacing: 10) {
                    Text("핵심 단어")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(keywords, id: \.self) { keyword in
                            Text("#\(keyword)")
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                // Custom Hexagonal Radar Chart
                VStack(alignment: .leading, spacing: 10) {
                    Text("정신 감정 상태 그래프")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    RadarChartView(scores: emotionScores, size: 220)
                        .padding()
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(16)
                        .padding(.horizontal)
                }
                
                // Attached Photos Preview & Management
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "photo.stack.fill")
                            .foregroundColor(.accentColor)
                        Text("첨부된 사진 (\(attachedImages.count)장)")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            ImageFileManager.shared.pickImagesFromPanel { images in
                                self.attachedImages.append(contentsOf: images)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("사진 추가")
                            }
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    
                    if attachedImages.isEmpty {
                        Button(action: {
                            ImageFileManager.shared.pickImagesFromPanel { images in
                                self.attachedImages.append(contentsOf: images)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 20))
                                Text("사진을 추가하여 일기를 더 풍성하게 남겨보세요 (클릭 또는 드래그 & 드롭)")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .background(Color.secondary.opacity(0.04))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    } else {
                        photoThumbnailStrip
                    }
                }
                
                // Final Synthesized Diary Content
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("완성된 일기")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("자유롭게 수정할 수 있습니다")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    TextEditor(text: $finalContent)
                        .font(.body)
                        .lineSpacing(6)
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .frame(minHeight: 180)
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
    }
    
    // MARK: - Functions
    
    private func setupSilenceAutoSend() {
        speechRecognizer.onSilenceDetected = { [self] recognizedText in
            // 상시 마이크 모드 - 스트리밍 또는 TTS 낭독 중이 아닐 때 자동 전송
            guard !isStreaming && !ttsService.isSpeaking else { return }
            let clean = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !isLoading {
                DispatchQueue.main.async {
                    self.chatInput = clean
                    self.sendChatMessage()
                }
            }
        }
    }
    
    private func setupTTSCallbacks() {
        ttsService.onSpeechStarted = {
            DispatchQueue.main.async {
                self.chatInput = ""
                self.speechRecognizer.pauseForTTS()
            }
        }
        ttsService.onSpeechFinished = {
            DispatchQueue.main.async {
                self.chatInput = ""
                if !self.isStreaming {
                    self.speechRecognizer.resumeFromTTS(delay: 0.6)
                }
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            if isStreaming {
                proxy.scrollTo("ai_streaming", anchor: .bottom)
            } else if !currentQuestion.isEmpty {
                proxy.scrollTo("ai_question", anchor: .bottom)
            } else if let last = chatHistory.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
    
    // Start Initial Conversation with AI greeting
    private func startInitialConversation() {
        let question = llmService.getInitialQuestion()
        self.currentQuestion = question
        if ttsService.autoReadAIResponse {
            ttsService.speak(text: question)
        }
    }
    
    // User submits chat response with Streaming
    private func sendChatMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && !isStreaming else { return }
        
        if ttsService.isSpeaking {
            ttsService.stop()
        }
        
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
        
        if !currentQuestion.isEmpty {
            chatHistory.append(ChatMessage(isUser: false, text: currentQuestion))
            currentQuestion = ""
        }
        
        let userMsg = ChatMessage(isUser: true, text: text)
        chatHistory.append(userMsg)
        chatInput = ""
        
        isStreaming = true
        streamingText = ""
        isLoading = true
        let tempHistory = chatHistory
        
        Task {
            do {
                let response = try await llmService.chatNextTurnStream(
                    history: tempHistory,
                    forceFinalize: false,
                    onChunk: { chunk in
                        self.streamingText += chunk
                    }
                )
                await MainActor.run {
                    self.isStreaming = false
                    self.streamingText = ""
                    self.isLoading = false
                    
                    if let draft = response.liveDraft, !draft.isEmpty {
                        self.liveDraft = draft
                    }
                    
                    if response.isComplete {
                        self.currentQuestion = ""
                        self.finalContent = response.finalDiaryContent ?? self.liveDraft
                        analyzeFinalDiary()
                    } else {
                        let nextQ = response.question ?? "오늘 이야기와 관련해서 더 말씀해주시고 싶은 부분이 있으신가요?"
                        self.currentQuestion = nextQ
                        if self.ttsService.autoReadAIResponse {
                            self.ttsService.speak(text: nextQ)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isStreaming = false
                    self.streamingText = ""
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // Click button to complete immediately with Streaming
    private func finalizeDiaryDirectly() {
        guard !isStreaming else { return }
        isLoading = true
        isStreaming = true
        streamingText = ""
        
        var tempHistory = chatHistory
        let pendingText = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pendingText.isEmpty {
            if !currentQuestion.isEmpty {
                tempHistory.append(ChatMessage(isUser: false, text: currentQuestion))
            }
            tempHistory.append(ChatMessage(isUser: true, text: pendingText))
            chatInput = ""
        }
        
        Task {
            do {
                let response = try await llmService.chatNextTurnStream(
                    history: tempHistory,
                    forceFinalize: true,
                    onChunk: { chunk in
                        self.streamingText += chunk
                    }
                )
                await MainActor.run {
                    self.isStreaming = false
                    self.streamingText = ""
                    self.isLoading = false
                    self.currentQuestion = ""
                    self.finalContent = response.finalDiaryContent ?? self.liveDraft
                    if self.finalContent.isEmpty {
                        self.finalContent = tempHistory.filter { $0.isUser }.map { $0.text }.joined(separator: "\n\n")
                    }
                    analyzeFinalDiary()
                }
            } catch {
                await MainActor.run {
                    self.isStreaming = false
                    self.streamingText = ""
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // Take final compiled text, extract summary, keywords, emotions, and emoji
    private func analyzeFinalDiary() {
        isLoading = true
        let textToAnalyze = finalContent
        
        Task {
            do {
                let result = try await llmService.analyzeDiary(content: textToAnalyze)
                await MainActor.run {
                    self.isLoading = false
                    self.summary = result.summary
                    self.keywords = result.keywords
                    self.moodEmoji = result.moodEmoji
                    self.emotionScores = result.emotionScores
                    
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MM월 dd일 "
                    self.diaryTitle = formatter.string(from: Date()) + (result.keywords.first ?? "오늘") + " 일기"
                    
                    self.step = .preview
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // Save to local store
    private func saveDiary() {
        var savedImageFilenames: [String] = []
        for img in attachedImages {
            if let filename = ImageFileManager.shared.saveImage(img) {
                savedImageFilenames.append(filename)
            }
        }
        
        let entry = DiaryEntry(
            date: Date(),
            title: diaryTitle,
            content: finalContent,
            voiceDraft: liveDraft.isEmpty ? nil : liveDraft,
            keywords: keywords,
            moodEmoji: moodEmoji,
            emotionScores: emotionScores,
            chatHistory: chatHistory,
            images: savedImageFilenames
        )
        diaryStore.add(entry)
        dismiss()
    }
    
    // Drag & Drop Handler
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage {
                        DispatchQueue.main.async {
                            self.attachedImages.append(image)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil),
                       let image = NSImage(contentsOf: url) {
                        DispatchQueue.main.async {
                            self.attachedImages.append(image)
                        }
                    } else if let url = item as? URL,
                              let image = NSImage(contentsOf: url) {
                        DispatchQueue.main.async {
                            self.attachedImages.append(image)
                        }
                    }
                }
            }
        }
        return true
    }
    
    // Photo Thumbnails Strip
    private var photoThumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(attachedImages.enumerated()), id: \.offset) { index, img in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 68, height: 68)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                            .onTapGesture {
                                selectedPreviewImage = img
                            }
                        
                        Button(action: {
                            withAnimation {
                                _ = attachedImages.remove(at: index)
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .background(Circle().fill(Color.black.opacity(0.7)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                        .help("사진 삭제")
                    }
                }
                
                Button(action: {
                    ImageFileManager.shared.pickImagesFromPanel { images in
                        self.attachedImages.append(contentsOf: images)
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.accentColor)
                        Text("추가")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    .frame(width: 68, height: 68)
                    .background(Color.accentColor.opacity(0.08))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    )
                }
                .buttonStyle(.plain)
                .help("사진 추가하기")
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}

// Modal and helper models
struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: NSImage
}

struct ImageViewerModal: View {
    let image: NSImage
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("사진 확대 보기")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding([.top, .horizontal])
            
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 800, maxHeight: 600)
                .cornerRadius(12)
                .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 460, minHeight: 360)
    }
}

// Helper Subviews

struct WaveformView: View {
    var isRecording: Bool
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<18) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isRecording ? Color.red : Color.secondary.opacity(0.3))
                    .frame(width: 3, height: isRecording ? CGFloat.random(in: 8...24) : 6)
                    .animation(isRecording ? .easeInOut(duration: 0.3).repeatForever(autoreverses: true).delay(Double(index) * 0.02) : .default, value: isRecording)
            }
        }
    }
}

struct ChatBubble: View {
    var message: ChatMessage
    var modelName: String
    @EnvironmentObject var ttsService: TTSService
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.isUser {
                Spacer()
                Text(message.text)
                    .font(.body)
                    .lineSpacing(4)
                    .padding(14)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 16))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("AI 비서 (\(modelName))")
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)
                        
                        Spacer()
                        
                        Button(action: {
                            ttsService.togglePlayback(for: message.text)
                        }) {
                            Image(systemName: (ttsService.isSpeaking && ttsService.currentlySpeakingText == message.text) ? "speaker.slash.fill" : "speaker.wave.2")
                                .font(.system(size: 12))
                                .foregroundColor(ttsService.isSpeaking ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("음성으로 다시 듣기")
                    }
                    
                    Text(message.text)
                        .font(.body)
                        .lineSpacing(4)
                        .padding(14)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(14)
                }
                Spacer()
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    NewDiaryView()
        .environmentObject(DiaryStore())
        .environmentObject(LLMService())
}
