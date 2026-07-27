import Foundation
import Combine

struct GeminiModelInfo: Identifiable, Codable, Hashable {
    var id: String            // e.g. "models/gemini-1.5-flash" or "gemini-1.5-flash"
    var name: String          // Raw name
    var displayName: String   // Human friendly label
    var description: String
    var isRecommended: Bool
    
    var cleanId: String {
        if id.hasPrefix("models/") {
            return String(id.dropFirst(7))
        }
        return id
    }
}

class LLMService: ObservableObject {
    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "gemini_api_key")
            if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.useSimulation = false
            }
        }
    }
    
    @Published var useSimulation: Bool {
        didSet {
            UserDefaults.standard.set(useSimulation, forKey: "use_simulation")
        }
    }
    
    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "selected_gemini_model")
        }
    }
    
    @Published var availableModels: [GeminiModelInfo] = []
    @Published var isLoadingModels: Bool = false
    @Published var fetchModelsError: String? = nil
    
    // Official Google Gemini API model list
    static let defaultModels: [GeminiModelInfo] = [
        GeminiModelInfo(
            id: "gemini-1.5-flash",
            name: "gemini-1.5-flash",
            displayName: "Gemini 1.5 Flash (기본 권장)",
            description: "빠른 속도와 높은 정확도를 자랑하는 공식 권장 모델",
            isRecommended: true
        ),
        GeminiModelInfo(
            id: "gemini-2.0-flash",
            name: "gemini-2.0-flash",
            displayName: "Gemini 2.0 Flash",
            description: "차세대 초고속 응답 실시간 대화 모델",
            isRecommended: false
        ),
        GeminiModelInfo(
            id: "gemini-1.5-pro",
            name: "gemini-1.5-pro",
            displayName: "Gemini 1.5 Pro",
            description: "깊이 있는 심리 감정 분석 및 복잡한 추론 전문 모델",
            isRecommended: false
        )
    ]
    
    init() {
        let savedKey = UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
        self.apiKey = savedKey
        
        if !savedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.useSimulation = UserDefaults.standard.object(forKey: "use_simulation") as? Bool ?? false
        } else {
            self.useSimulation = UserDefaults.standard.object(forKey: "use_simulation") as? Bool ?? true
        }
        
        let savedModel = UserDefaults.standard.string(forKey: "selected_gemini_model") ?? "gemini-1.5-flash"
        if savedModel == "gemini-2.5-flash" || savedModel == "gemini-2.5-pro" {
            self.selectedModel = "gemini-1.5-flash"
        } else {
            self.selectedModel = savedModel
        }
        
        self.availableModels = LLMService.defaultModels
    }
    
    var selectedModelDisplayName: String {
        let clean = selectedModel.hasPrefix("models/") ? String(selectedModel.dropFirst(7)) : selectedModel
        if let found = availableModels.first(where: { $0.cleanId == clean || $0.id == selectedModel }) {
            return found.displayName
        }
        return clean
    }
    
    // Initial AI opening question
    func getInitialQuestion() -> String {
        let greetings = [
            "안녕하세요! 오늘 하루는 어떻게 보내셨나요? 마음이나 기억에 가장 크게 남는 이야기부터 편하게 말씀해 주세요.",
            "오늘 당신의 하루가 궁금해요. 특별한 일이나 마음을 스쳐 지나간 생각이 있었다면 무엇이든 들려주시겠어요?",
            "어서오세요! 오늘 있었던 사건이나 느꼈던 감정 중 나눌 이야기가 있다면 편안하게 이야기해 보세요."
        ]
        return greetings.randomElement()!
    }
    
    // Structs for JSON responses
    struct AnalysisResponse: Codable {
        let summary: String
        let keywords: [String]
        let moodEmoji: String
        let emotionScores: SimulatedScores
        
        struct SimulatedScores: Codable {
            let joy: Double
            let sadness: Double
            let anger: Double
            let anxiety: Double
            let serenity: Double
            let stress: Double
        }
    }
    
    struct ChatTurnResponse: Codable {
        let question: String?           // Next follow-up question ("꼬리 질문")
        let liveDraft: String?          // Incremental, synthesized diary draft built live from chat so far
        let finalDiaryContent: String?  // Final synthesized diary entry when complete
        let isComplete: Bool
    }
    
    // Test API Connection
    @MainActor
    func testApiConnection() async -> (success: Bool, message: String) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            return (false, "Gemini API 키가 입력되지 않았습니다.")
        }
        
        let modelTarget = selectedModel.hasPrefix("models/") ? String(selectedModel.dropFirst(7)) : selectedModel
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelTarget):generateContent?key=\(cleanKey)"
        guard let url = URL(string: urlString) else {
            return (false, "유효하지 않은 URL 형식입니다.")
        }
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": "Hello"]]
                ]
            ]
        ]
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "서버 응답을 받지 못했습니다.")
            }
            
            if httpResponse.statusCode == 200 {
                await fetchAvailableModels()
                return (true, "Google Gemini API 연동 성공! (\(selectedModelDisplayName))")
            } else {
                let errStr = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                if httpResponse.statusCode == 400 || httpResponse.statusCode == 403 {
                    return (false, "API 키가 잘못되었거나 승인되지 않았습니다. (HTTP \(httpResponse.statusCode))\nGoogle AI Studio에서 API 키를 확인해 주세요.")
                } else if httpResponse.statusCode == 404 {
                    return (false, "선택한 모델('\(modelTarget)')을 해당 API 키로 찾을 수 없습니다. 'gemini-1.5-flash'를 선택하세요.")
                } else {
                    return (false, "API 오류 (HTTP \(httpResponse.statusCode)): \(errStr)")
                }
            }
        } catch {
            return (false, "네트워크 연결 실패: \(error.localizedDescription)")
        }
    }
    
    // Fetch available models for the user's API Key
    @MainActor
    func fetchAvailableModels() async {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            self.availableModels = LLMService.defaultModels
            return
        }
        
        self.isLoadingModels = true
        self.fetchModelsError = nil
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models?key=\(cleanKey)"
        guard let url = URL(string: urlString) else {
            self.isLoadingModels = false
            self.fetchModelsError = "유효하지 않은 API URL입니다."
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errStr = String(data: data, encoding: .utf8) ?? "API 오류"
                throw NSError(domain: "LLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "모델 목록 조회 실패: \(errStr)"])
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let modelsArray = json["models"] as? [[String: Any]] {
                
                var fetched: [GeminiModelInfo] = []
                
                for item in modelsArray {
                    guard let name = item["name"] as? String,
                          let methods = item["supportedGenerationMethods"] as? [String],
                          methods.contains("generateContent") else {
                        continue
                    }
                    
                    let dispName = (item["displayName"] as? String) ?? name
                    let desc = (item["description"] as? String) ?? "Gemini AI 모델"
                    let isRec = name.contains("1.5-flash") || name.contains("flash")
                    
                    fetched.append(GeminiModelInfo(
                        id: name,
                        name: name,
                        displayName: dispName,
                        description: desc,
                        isRecommended: isRec
                    ))
                }
                
                if !fetched.isEmpty {
                    self.availableModels = fetched
                } else {
                    self.availableModels = LLMService.defaultModels
                }
            } else {
                self.availableModels = LLMService.defaultModels
            }
            self.isLoadingModels = false
        } catch {
            self.fetchModelsError = error.localizedDescription
            self.isLoadingModels = false
            self.availableModels = LLMService.defaultModels
        }
    }
    
    // Interactive Chat turn using Gemini API with Real-Time Streaming (SSE)
    func chatNextTurnStream(
        history: [ChatMessage],
        forceFinalize: Bool = false,
        onChunk: @escaping (String) -> Void
    ) async throws -> ChatTurnResponse {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if useSimulation || cleanKey.isEmpty {
            let response = simulateChatTurn(history: history, forceFinalize: forceFinalize)
            if let q = response.question {
                for char in q {
                    onChunk(String(char))
                    try? await Task.sleep(nanoseconds: 25_000_000)
                }
            }
            return response
        }
        
        let modelTarget = selectedModel.hasPrefix("models/") ? String(selectedModel.dropFirst(7)) : selectedModel
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelTarget):streamGenerateContent?key=\(cleanKey)&alt=sse"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "LLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        let systemPrompt: String
        if forceFinalize {
            systemPrompt = """
            You are an empathetic diary assistant. The user wants to finish the diary dialogue right now.
            Based on all user statements in the conversation history so far:
            1. Write a complete, polished, beautiful first-person Korean diary entry in "finalDiaryContent".
            2. Set "isComplete" to true.
            3. Set "question" to null.
            4. Set "liveDraft" to null.
            
            Ensure you output valid JSON matching this schema:
            {
              "question": null,
              "liveDraft": null,
              "finalDiaryContent": "string",
              "isComplete": true
            }
            """
        } else {
            systemPrompt = """
            You are an empathetic, skilled mental health diary assistant. You are conversing in real-time with the user to help them write a rich personal diary.
            Review the entire chat history.
            Your goals:
            1. Formulate ONE insightful, warm, specific follow-up question ("꼬리 질문") in Korean to explore missing context, specific events, or deeper emotions that the user hasn't mentioned yet.
            2. Synthesize a live draft ("liveDraft") of a first-person Korean diary entry based on everything the user has shared in the conversation up to this moment.
            3. If the user explicitly asks to stop, says there's nothing more to add, or if the conversation is complete (after 3-4 turns), set "isComplete" to true, write the complete final diary in "finalDiaryContent", and set "question" and "liveDraft" to null. Otherwise set "isComplete" to false.
            
            Ensure you output valid JSON matching this schema:
            {
              "question": "string or null",
              "liveDraft": "string or null",
              "finalDiaryContent": "string or null",
              "isComplete": boolean
            }
            """
        }
        
        var conversationContext = "Full Conversation History:\n"
        for msg in history {
            let role = msg.isUser ? "User" : "AI Assistant"
            conversationContext += "\(role): \(msg.text)\n"
        }
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": systemPrompt + "\n\n" + conversationContext]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json"
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "LLMService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Gemini Streaming API 오류 (\(modelTarget))"])
        }
        
        var fullTextAccumulator = ""
        
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data: ") else { continue }
            let jsonString = String(trimmed.dropFirst(6))
            if jsonString == "[DONE]" { break }
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let contentNode = firstCandidate["content"] as? [String: Any],
                  let parts = contentNode["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let chunkText = firstPart["text"] as? String else {
                continue
            }
            
            fullTextAccumulator += chunkText
            await MainActor.run {
                onChunk(chunkText)
            }
        }
        
        let cleanFullText = fullTextAccumulator.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let responseData = cleanFullText.data(using: .utf8) else {
            throw NSError(domain: "LLMService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Encoding error"])
        }
        
        return try JSONDecoder().decode(ChatTurnResponse.self, from: responseData)
    }
    
    // Analyze final diary content
    func analyzeDiary(content: String) async throws -> (summary: String, keywords: [String], moodEmoji: String, emotionScores: EmotionScores) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if useSimulation || cleanKey.isEmpty {
            return simulateAnalysis(content: content)
        }
        
        let modelTarget = selectedModel.hasPrefix("models/") ? String(selectedModel.dropFirst(7)) : selectedModel
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelTarget):generateContent?key=\(cleanKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "LLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        let systemPrompt = """
        You are an expert mental health diary analyzer. Analyze the diary content and return a JSON object with:
        1. "summary": A brief 1-2 sentence summary of the diary entry in Korean.
        2. "keywords": 3-5 Korean keywords that capture the core topics, without '#' symbol.
        3. "moodEmoji": A single emoji representing the dominant mood (e.g. 😊, 😭, 😡, 😭, 😌, 😫).
        4. "emotionScores": A JSON object containing scores from 0.0 to 10.0 for: "joy", "sadness", "anger", "anxiety", "serenity", "stress".
        
        Ensure you output valid JSON matching this schema:
        {
          "summary": "string",
          "keywords": ["string"],
          "moodEmoji": "string",
          "emotionScores": {
            "joy": 8.0,
            "sadness": 1.0,
            "anger": 0.0,
            "anxiety": 2.0,
            "serenity": 8.0,
            "stress": 1.0
          }
        }
        """
        
        let prompt = "Analyze this diary:\n\"\"\"\n\(content)\n\"\"\""
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": systemPrompt + "\n\n" + prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json"
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown HTTP error"
            throw NSError(domain: "LLMService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Gemini API 오류 (\(modelTarget)): \(errorMsg)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let contentNode = firstCandidate["content"] as? [String: Any],
              let parts = contentNode["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw NSError(domain: "LLMService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse API structure"])
        }
        
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let responseData = cleanText.data(using: .utf8) else {
            throw NSError(domain: "LLMService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Encoding error"])
        }
        
        let analysis = try JSONDecoder().decode(AnalysisResponse.self, from: responseData)
        
        let scores = EmotionScores(
            joy: analysis.emotionScores.joy,
            sadness: analysis.emotionScores.sadness,
            anger: analysis.emotionScores.anger,
            anxiety: analysis.emotionScores.anxiety,
            serenity: analysis.emotionScores.serenity,
            stress: analysis.emotionScores.stress
        )
        
        return (analysis.summary, analysis.keywords, analysis.moodEmoji, scores)
    }
    
    // --- SIMULATOR HEURISTICS ---
    
    private func simulateChatTurn(history: [ChatMessage], forceFinalize: Bool) -> ChatTurnResponse {
        let userMsgs = history.filter({ $0.isUser })
        let userRepliesCount = userMsgs.count
        
        if forceFinalize || userRepliesCount >= 3 {
            var combinedText = userMsgs.map { $0.text }.joined(separator: " ")
            if combinedText.isEmpty { combinedText = "오늘 하루는 평온하게 지나갔다." }
            
            let finalDiary = """
            \(combinedText)
            
            오늘 대화를 나누며 나의 생각과 기분을 차근차근 되짚어보았다. 말로 털어놓으니 엉켜있던 감정들이 차분하게 정돈되는 느낌이다. 내일도 나 스스로의 마음에 더 집중하는 하루를 보내야겠다.
            """
            
            return ChatTurnResponse(
                question: nil,
                liveDraft: nil,
                finalDiaryContent: finalDiary,
                isComplete: true
            )
        }
        
        let lastUserMessage = userMsgs.last?.text ?? ""
        let lower = lastUserMessage.lowercased()
        
        let question: String
        if lower.contains("회사") || lower.contains("일") || lower.contains("프로젝트") || lower.contains("업무") {
            question = "오늘 업무나 프로젝트 과정에서 특별히 가슴이 두근거리거나 스트레스를 받았던 구체적인 순간은 언제였나요?"
        } else if lower.contains("친구") || lower.contains("사람") || lower.contains("싸움") || lower.contains("대화") {
            question = "그때 대화하면서 본인의 진짜 마음속 생각은 어땠나요? 혹시 미처 전하지 못해 아쉬웠던 말이 있으신가요?"
        } else if lower.contains("산책") || lower.contains("커피") || lower.contains("휴식") || lower.contains("음악") {
            question = "그 여유로운 순간에 마음에 어떤 변화나 힐링이 찾아왔는지 조금 더 들려주세요."
        } else {
            question = "그 일을 겪으셨을 때 마음속으로 어떤 감정이 가장 크게 느껴지셨나요? 그때의 상황을 조금 더 자세히 알고 싶어요."
        }
        
        let compiledDraft = userMsgs.map { $0.text }.joined(separator: "\n\n")
        let liveDraft = compiledDraft.isEmpty ? "오늘 이야기를 나누기 시작했습니다." : "오늘 이야기:\n" + compiledDraft
        
        return ChatTurnResponse(
            question: question,
            liveDraft: liveDraft,
            finalDiaryContent: nil,
            isComplete: false
        )
    }
    
    private func simulateAnalysis(content: String) -> (summary: String, keywords: [String], moodEmoji: String, emotionScores: EmotionScores) {
        var joy = 4.0
        var sadness = 2.0
        var anger = 1.0
        var anxiety = 2.0
        var serenity = 5.0
        var stress = 2.0
        
        var matchedKeywords: Set<String> = []
        var emoji = "😌"
        
        let lower = content.lowercased()
        
        if lower.contains("행복") || lower.contains("기뻐") || lower.contains("좋았") || lower.contains("감사") || lower.contains("웃") {
            joy += 4.0
            serenity += 3.0
            matchedKeywords.insert("행복")
            emoji = "😊"
        }
        if lower.contains("우울") || lower.contains("슬프") || lower.contains("눈물") || lower.contains("아프") || lower.contains("후회") {
            sadness += 5.0
            joy -= 2.0
            matchedKeywords.insert("슬픔")
            emoji = "😭"
        }
        if lower.contains("화나") || lower.contains("짜증") || lower.contains("욱") || lower.contains("싸웠") {
            anger += 5.5
            serenity -= 3.0
            matchedKeywords.insert("갈등")
            emoji = "😡"
        }
        if lower.contains("불안") || lower.contains("걱정") || lower.contains("긴장") || lower.contains("실수") {
            anxiety += 5.5
            serenity -= 2.0
            matchedKeywords.insert("걱정")
            emoji = "😨"
        }
        if lower.contains("평온") || lower.contains("커피") || lower.contains("책") || lower.contains("산책") || lower.contains("휴식") {
            serenity += 4.0
            stress -= 1.5
            matchedKeywords.insert("여유")
            emoji = "😌"
        }
        if lower.contains("스트레스") || lower.contains("피곤") || lower.contains("업무") || lower.contains("마감") {
            stress += 5.0
            serenity -= 2.0
            matchedKeywords.insert("스트레스")
            emoji = "😫"
        }
        
        let words = ["산책", "프로젝트", "회의", "가족", "친구", "회사", "운동", "식사", "휴식", "공부", "날씨"]
        for word in words {
            if lower.contains(word) {
                matchedKeywords.insert(word)
            }
        }
        
        if matchedKeywords.count < 3 {
            matchedKeywords.insert("일상")
            matchedKeywords.insert("대화기록")
        }
        
        let finalKeywords = Array(matchedKeywords.prefix(4))
        let summary = "오늘 일기는 \(finalKeywords.joined(separator: ", "))에 관한 대화입니다. AI와의 차분한 대화를 통해 하루의 마음 상태를 점진적으로 정돈했습니다."
        
        let scores = EmotionScores(
            joy: min(10.0, max(0.0, joy)),
            sadness: min(10.0, max(0.0, sadness)),
            anger: min(10.0, max(0.0, anger)),
            anxiety: min(10.0, max(0.0, anxiety)),
            serenity: min(10.0, max(0.0, serenity)),
            stress: min(10.0, max(0.0, stress))
        )
        
        return (summary, finalKeywords, emoji, scores)
    }
}
