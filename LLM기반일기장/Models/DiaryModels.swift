import Foundation
import Combine
import SwiftUI

struct EmotionScores: Codable, Equatable {
    var joy: Double      // 기쁨 (0 to 10)
    var sadness: Double  // 슬픔 (0 to 10)
    var anger: Double    // 분노 (0 to 10)
    var anxiety: Double  // 불안/공포 (0 to 10)
    var serenity: Double // 평온/신뢰 (0 to 10)
    var stress: Double   // 피로/스트레스 (0 to 10)

    /// 6가지 감정을 종합한 단일 무드 지수 (0~10)
    /// 긍정 감정(기쁨·평온)은 더하고 부정 감정(슬픔·분노·불안·스트레스)은 뺀 후 정규화
    var moodScore: Double {
        let positive = (joy * 2.0 + serenity * 2.0)
        let negative = (sadness + anger + anxiety + stress)
        let raw = (positive - negative + 20.0) / 4.0  // [-20..20] → [0..10]
        return max(0, min(10, raw))
    }

    static var empty: EmotionScores {
        EmotionScores(joy: 0, sadness: 0, anger: 0, anxiety: 0, serenity: 0, stress: 0)
    }
}


struct ChatMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    var isUser: Bool
    var text: String
    var timestamp = Date()
}

struct DiaryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var title: String
    var content: String
    var voiceDraft: String?
    var keywords: [String]
    var moodEmoji: String
    var emotionScores: EmotionScores
    var chatHistory: [ChatMessage]
    var images: [String] = [] // 로컬 Documents/diary_images 폴더에 저장된 파일명 목록
    
    enum CodingKeys: String, CodingKey {
        case id, date, title, content, voiceDraft, keywords, moodEmoji, emotionScores, chatHistory, images
    }
    
    init(id: UUID = UUID(),
         date: Date = Date(),
         title: String,
         content: String,
         voiceDraft: String? = nil,
         keywords: [String] = [],
         moodEmoji: String = "😌",
         emotionScores: EmotionScores = .empty,
         chatHistory: [ChatMessage] = [],
         images: [String] = []) {
        self.id = id
        self.date = date
        self.title = title
        self.content = content
        self.voiceDraft = voiceDraft
        self.keywords = keywords
        self.moodEmoji = moodEmoji
        self.emotionScores = emotionScores
        self.chatHistory = chatHistory
        self.images = images
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.date = try container.decode(Date.self, forKey: .date)
        self.title = try container.decode(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.voiceDraft = try container.decodeIfPresent(String.self, forKey: .voiceDraft)
        self.keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        self.moodEmoji = try container.decodeIfPresent(String.self, forKey: .moodEmoji) ?? "😌"
        self.emotionScores = try container.decodeIfPresent(EmotionScores.self, forKey: .emotionScores) ?? .empty
        self.chatHistory = try container.decodeIfPresent([ChatMessage].self, forKey: .chatHistory) ?? []
        self.images = try container.decodeIfPresent([String].self, forKey: .images) ?? []
    }
}

class DiaryStore: ObservableObject {
    @Published var entries: [DiaryEntry] = []
    
    private var saveURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("diary_entries.json")
    }
    
    init() {
        load()
    }
    
    func load() {
        let url = saveURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            self.entries = []
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([DiaryEntry].self, from: data)
            DispatchQueue.main.async {
                self.entries = decoded.sorted(by: { $0.date > $1.date })
            }
        } catch {
            print("Failed to load diary entries: \(error)")
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([DiaryEntry].self, from: data)
                DispatchQueue.main.async {
                    self.entries = decoded.sorted(by: { $0.date > $1.date })
                }
            } catch {
                print("Failed absolute fallback decode: \(error)")
                self.entries = []
            }
        }
    }
    
    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(entries)
            try data.write(to: saveURL, options: [.atomicWrite])
        } catch {
            print("Failed to save diary entries: \(error)")
        }
    }
    
    func add(_ entry: DiaryEntry) {
        entries.append(entry)
        entries.sort(by: { $0.date > $1.date })
        save()
    }
    
    func delete(at offsets: IndexSet) {
        for index in offsets {
            if index < entries.count {
                ImageFileManager.shared.deleteImages(filenames: entries[index].images)
            }
        }
        entries.remove(atOffsets: offsets)
        save()
    }
    
    func delete(_ entry: DiaryEntry) {
        ImageFileManager.shared.deleteImages(filenames: entry.images)
        entries.removeAll(where: { $0.id == entry.id })
        save()
    }
    
    func clearAll() {
        for entry in entries {
            ImageFileManager.shared.deleteImages(filenames: entry.images)
        }
        entries = []
        save()
    }
    
    func loadMockDataIfEmpty() {
        guard entries.isEmpty else { return }
        
        let calendar = Calendar.current
        let today = Date()
        
        let mock1 = DiaryEntry(
            date: today,
            title: "기분 좋은 공원 산책",
            content: "오늘 점심 시간에 근처 공원을 한 바퀴 돌았다. 바람이 불어서 시원했고 푸른 나무들을 보니 마음이 평온해졌다. 업무 스트레스가 조금 날아간 기분이다. 요즘 너무 컴퓨터 앞에만 앉아있었던 것 같은데 종종 나와서 걸어야겠다.",
            voiceDraft: "오늘 점심 시간에 공원 산책을 했다. 날씨가 좋고 바람도 불어서 정말 시원했다. 나무들을 보니까 머리가 맑아지고 마음이 평온해졌다. 종종 걸어야지.",
            keywords: ["산책", "날씨", "평온", "휴식"],
            moodEmoji: "😌",
            emotionScores: EmotionScores(joy: 8.0, sadness: 1.0, anger: 0.0, anxiety: 1.0, serenity: 8.5, stress: 2.0),
            chatHistory: [
                ChatMessage(isUser: true, text: "오늘 점심 시간에 공원 산책을 했다. 날씨가 좋고 시원했다."),
                ChatMessage(isUser: false, text: "산책을 하시면서 구체적으로 어떤 점이 좋았나요? 마음의 변화가 있었는지 궁금해요."),
                ChatMessage(isUser: true, text: "나무들을 보니까 머리가 맑아지고 업무 스트레스가 좀 날아간 것 같아서 평온해졌다. 종종 걷기로 결심했다.")
            ]
        )
        
        let mock2 = DiaryEntry(
            date: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
            title: "중요한 프로젝트 마감일",
            content: "오늘 드디어 몇 주간 준비한 프로젝트를 마감하여 제출했다. 제출 직전까지 오류가 있어서 가슴이 두근거리고 엄청 불안했다. 다행히 팀원들의 도움으로 잘 마무리할 수 있었지만 몸과 마음이 너무 지쳐서 끝나자마자 뻗어버렸다. 그래도 끝내서 후련하다.",
            voiceDraft: "프로젝트를 드디어 다 제출했다. 제출 전까지 오류가 나서 너무 가슴 졸이고 스트레스 받았다. 팀원들이랑 밤새며 겨우 해결해서 냈는데 진짜 피곤하다. 그래도 해내서 다행이다.",
            keywords: ["프로젝트", "마감", "스트레스", "안도"],
            moodEmoji: "😫",
            emotionScores: EmotionScores(joy: 6.0, sadness: 2.0, anger: 1.0, anxiety: 7.5, serenity: 4.0, stress: 8.0),
            chatHistory: [
                ChatMessage(isUser: true, text: "프로젝트 제출 완료. 마감 직전까지 오류 나서 미치는 줄 알았다. 밤새서 진짜 지쳤는데 끝내서 다행이다."),
                ChatMessage(isUser: false, text: "마감 직전 오류로 정말 불안하셨겠어요. 해결하고 나서는 어떤 감정이 드셨나요? 도움을 준 사람도 있었나요?"),
                ChatMessage(isUser: true, text: "팀원들이 도와줘서 해결했다. 끝나니까 너무 지쳤지만 다행이라는 안도감과 후련함이 교차한다.")
            ]
        )
        
        let mock3 = DiaryEntry(
            date: calendar.date(byAdding: .day, value: -3, to: today) ?? today,
            title: "사소한 의견 충돌과 화해",
            content: "가까운 친구와 대화 도중 사소한 생각 차이로 말다툼을 하게 되었다. 처음에는 내 주장을 굽히기 싫어서 욱하는 감정이 들었는데, 집에 오면서 되짚어보니 내가 너무 예민하게 굴었던 것 같아 미안해졌다. 먼저 전화를 걸어 미안하다고 사과했고 친구도 흔쾌히 받아주며 웃었다. 관계를 지키는 게 자존심보다 훨씬 소중하다.",
            voiceDraft: "친구랑 사소한 일로 싸웠다. 내 자존심 세우느라 욱했는데 집에 오니까 후회됐다. 내가 너무 예민했던 거 같아서 전화를 걸어 사과했고 잘 화해했다.",
            keywords: ["친구", "다툼", "사과", "화해"],
            moodEmoji: "😊",
            emotionScores: EmotionScores(joy: 7.0, sadness: 3.0, anger: 5.0, anxiety: 2.0, serenity: 7.5, stress: 3.5),
            chatHistory: [
                ChatMessage(isUser: true, text: "친구랑 별것도 아닌 걸로 말싸움을 했다. 내 생각이 맞다고 우겼는데 후련하지 않고 찝찝했다."),
                ChatMessage(isUser: false, text: "자존심 때문에 속상하셨겠어요. 집으로 돌아오면서는 어떤 생각이 드셨나요? 관계는 어떻게 해결하셨는지 들려주세요."),
                ChatMessage(isUser: true, text: "후회가 밀려와서 전화를 했고 미안하다고 먼저 사과했다. 다행히 잘 풀었고 사과하길 참 잘했다는 생각이 든다.")
            ]
        )

        let mock4 = DiaryEntry(
            date: calendar.date(byAdding: .day, value: -5, to: today) ?? today,
            title: "비 오는 날의 차분함",
            content: "하루 종일 비가 내리는 흐린 날씨였다. 빗소리가 듣기 좋아 조용한 음악을 틀어놓고 따뜻한 커피를 마시며 책을 읽었다. 밖으로 나가지는 않았지만 집안에서의 차분하고 고즈넉한 시간이 큰 위로가 되었다. 가끔은 이런 정적인 하루도 마음을 채워준다.",
            voiceDraft: "비가 하루종일 오길래 조용히 음악 들으면서 커피 마시고 책 읽었다. 고요하고 차분한 시간이 참 좋았다.",
            keywords: ["비", "독서", "커피", "차분함"],
            moodEmoji: "😌",
            emotionScores: EmotionScores(joy: 7.5, sadness: 2.0, anger: 0.0, anxiety: 1.0, serenity: 9.0, stress: 1.0),
            chatHistory: []
        )
        
        let mock5 = DiaryEntry(
            date: calendar.date(byAdding: .day, value: -7, to: today) ?? today,
            title: "업무 실수로 인한 자책과 극복",
            content: "회사에서 메일 전송 오류로 작은 실수를 저질렀다. 다행히 큰 피해는 없었지만 하루 종일 스스로 한심하게 느껴지고 가슴이 턱 막힌 듯 답답하고 불안했다. 저녁에 가볍게 조깅을 하며 생각을 정리했다. 실수는 누구나 하는 것이니 다음부터 더 주의하면 된다고 나를 토닥였다.",
            voiceDraft: "회사에서 실수했다. 너무 부끄럽고 답답해서 계속 신경 쓰이고 자책하게 됐다. 저녁에 달리기 하면서 기분 전환을 하려고 애썼다.",
            keywords: ["실수", "불안", "자책", "조깅", "극복"],
            moodEmoji: "😭",
            emotionScores: EmotionScores(joy: 2.0, sadness: 7.0, anger: 2.0, anxiety: 8.0, serenity: 3.0, stress: 7.0),
            chatHistory: [
                ChatMessage(isUser: true, text: "회사에서 자잘한 실수를 해서 하루 종일 우울했다. 계속 내 잘못인 것 같아 자책했다."),
                ChatMessage(isUser: false, text: "일하면서 실수를 겪어 속상하고 불안하셨군요. 이 스트레스를 어떻게 해소하셨나요?"),
                ChatMessage(isUser: true, text: "조깅을 뛰면서 땀을 흘렸다. 뛰고 나니까 한결 개운해졌고, 다음부터 잘하면 된다고 다짐했다.")
            ]
        )

        entries = [mock1, mock2, mock3, mock4, mock5]
        save()
    }
}
