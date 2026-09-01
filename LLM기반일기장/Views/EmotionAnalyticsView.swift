import SwiftUI

// MARK: - 감정 분석 탭 메인 뷰
struct EmotionAnalyticsView: View {
    @EnvironmentObject var diaryStore: DiaryStore

    @State private var selectedPeriod = 1  // 0=전체, 1=30일, 2=7일
    @State private var selectedEmotionIndex: Int? = nil

    private let periodOptions = ["전체", "최근 30일", "최근 7일"]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {

                // 상단 헤더
                headerSection

                // 기간 선택
                Picker("기간", selection: $selectedPeriod) {
                    ForEach(Array(periodOptions.enumerated()), id: \.offset) { idx, name in
                        Text(name).tag(idx)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if filteredEntries.count < 2 {
                    emptyState
                } else {
                    // 1. 종합 무드 트렌드 (대형)
                    moodTrendSection

                    Divider().padding(.horizontal)

                    // 2. 6가지 감정 개별 그래프
                    individualEmotionSection

                    Divider().padding(.horizontal)

                    // 3. 상세 분석 인사이트 카드
                    insightSection

                    Divider().padding(.horizontal)

                    // 4. 감정 통계 요약
                    statsSection
                }
            }
            .padding(.vertical, 20)
        }
        .navigationTitle("감정 분석")
    }

    // MARK: - 헤더
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("감정 변화 분석")
                    .font(.title2.bold())
                Text("일기에서 추출된 감정 데이터를 시각화합니다")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(filteredEntries.count)개")
                    .font(.title3.bold())
                    .foregroundColor(.accentColor)
                Text("분석된 일기")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - 1. 종합 무드 트렌드 섹션
    private var moodTrendSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 섹션 제목 + 현재 무드 스코어
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("종합 무드 트렌드", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                    Text("기쁨·평온 ↑ / 슬픔·분노·불안·스트레스 ↓ 종합 지수")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let latest = moodDataPoints.last {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(String(format: "%.1f", latest.value))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(moodScoreColor(latest.value))
                        Text("최근 무드")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)

            // 무드 스코어 색상 범례
            HStack(spacing: 12) {
                ForEach([("😊 좋음 7+", Color.green), ("😐 보통 4~7", Color.yellow), ("😞 낮음 ~4", Color.red)], id: \.0) { item in
                    HStack(spacing: 4) {
                        Circle().fill(item.1).frame(width: 8, height: 8)
                        Text(item.0).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)

            // 그래프
            EmotionLineChart(
                dataPoints: moodDataPoints,
                color: .accentColor,
                title: "종합 무드",
                showDots: true,
                height: 180
            )
            .padding(.horizontal)
            .padding(.bottom, 4)

            // y축 레이블 안내
            HStack {
                Text("0 = 매우 부정")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("5 = 중립")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("10 = 매우 긍정")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    // MARK: - 2. 6가지 감정 개별 그래프
    private var individualEmotionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("감정별 변화 추이", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                Text("각 감정을 클릭해 상세 설명을 확인하세요")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // 2열 그리드
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(Array(emotionDefinitions.enumerated()), id: \.offset) { idx, def in
                    EmotionMiniChart(
                        title: def.name,
                        emoji: def.emoji,
                        color: def.color,
                        dataPoints: emotionDataPoints(for: idx),
                        isSelected: selectedEmotionIndex == idx
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            selectedEmotionIndex = (selectedEmotionIndex == idx) ? nil : idx
                        }
                    }
                }
            }
            .padding(.horizontal)

            // 선택된 감정 상세 설명
            if let selIdx = selectedEmotionIndex {
                emotionDetailCard(for: selIdx)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - 개별 감정 상세 설명 카드
    private func emotionDetailCard(for idx: Int) -> some View {
        let def = emotionDefinitions[idx]
        let pts = emotionDataPoints(for: idx)
        let avg = pts.isEmpty ? 0 : pts.reduce(0) { $0 + $1.value } / Double(pts.count)
        let maxPt = pts.max(by: { $0.value < $1.value })
        let minPt = pts.min(by: { $0.value < $1.value })
        let trend = trendDescription(for: pts, emotionDef: def)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(def.emoji)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(def.name) 상세 분석")
                        .font(.headline)
                    Text(def.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    withAnimation { selectedEmotionIndex = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 통계 3종
            HStack(spacing: 0) {
                statBadge(label: "평균", value: String(format: "%.1f", avg), color: def.color)
                Divider().frame(height: 40)
                statBadge(label: "최고 \(maxPt?.label ?? "")", value: String(format: "%.1f", maxPt?.value ?? 0), color: .green)
                Divider().frame(height: 40)
                statBadge(label: "최저 \(minPt?.label ?? "")", value: String(format: "%.1f", minPt?.value ?? 0), color: .red)
            }
            .frame(maxWidth: .infinity)
            .background(def.color.opacity(0.05))
            .cornerRadius(10)

            // 트렌드 설명 텍스트
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(def.color)
                Text(trend)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineSpacing(4)
            }
            .padding(12)
            .background(def.color.opacity(0.08))
            .cornerRadius(10)
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(def.color.opacity(0.3), lineWidth: 1))
        .shadow(color: def.color.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }

    private func statBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    // MARK: - 3. 인사이트 섹션
    private var insightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI 감정 인사이트", systemImage: "brain")
                .font(.headline)
                .padding(.horizontal)

            ForEach(generateInsights(), id: \.self) { insight in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 14))
                    Text(insight)
                        .font(.subheadline)
                        .lineSpacing(4)
                        .foregroundColor(.primary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.07))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - 4. 통계 요약 섹션
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("감정 평균 요약", systemImage: "chart.bar.fill")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(Array(emotionDefinitions.enumerated()), id: \.offset) { idx, def in
                    let pts = emotionDataPoints(for: idx)
                    let avg = pts.isEmpty ? 0 : pts.reduce(0) { $0 + $1.value } / Double(pts.count)
                    EmotionBarRow(name: def.name, emoji: def.emoji, color: def.color, value: avg, maxVal: 10)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 빈 상태
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 52))
                .foregroundColor(.secondary.opacity(0.4))
            Text("아직 분석할 데이터가 부족합니다")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("일기를 2개 이상 작성하면 감정 변화 그래프가 나타납니다")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 데이터 계산 헬퍼

    private var filteredEntries: [DiaryEntry] {
        let calendar = Calendar.current
        let now = Date()
        let sorted = diaryStore.entries.sorted { $0.date < $1.date }
        switch selectedPeriod {
        case 2:
            let cutoff = calendar.date(byAdding: .day, value: -7, to: now)!
            return sorted.filter { $0.date >= cutoff }
        case 1:
            let cutoff = calendar.date(byAdding: .day, value: -30, to: now)!
            return sorted.filter { $0.date >= cutoff }
        default:
            return sorted
        }
    }

    private var moodDataPoints: [EmotionDataPoint] {
        filteredEntries.map { entry in
            EmotionDataPoint(
                date: entry.date,
                value: entry.emotionScores.moodScore,
                emoji: entry.moodEmoji,
                label: entry.date.shortLabel()
            )
        }
    }

    private func emotionDataPoints(for idx: Int) -> [EmotionDataPoint] {
        let keyPath: (EmotionScores) -> Double
        switch idx {
        case 0: keyPath = { $0.joy }
        case 1: keyPath = { $0.sadness }
        case 2: keyPath = { $0.anger }
        case 3: keyPath = { $0.anxiety }
        case 4: keyPath = { $0.serenity }
        default: keyPath = { $0.stress }
        }
        return filteredEntries.map { entry in
            EmotionDataPoint(
                date: entry.date,
                value: keyPath(entry.emotionScores),
                emoji: emotionDefinitions[idx].emoji,
                label: entry.date.shortLabel()
            )
        }
    }

    // MARK: - 인사이트 텍스트 생성
    private func generateInsights() -> [String] {
        guard filteredEntries.count >= 2 else { return [] }
        var insights: [String] = []

        let moodPts = moodDataPoints
        let first = moodPts.prefix(moodPts.count / 2).map(\.value)
        let second = moodPts.suffix(moodPts.count / 2).map(\.value)
        let firstAvg = first.reduce(0, +) / Double(max(first.count, 1))
        let secondAvg = second.reduce(0, +) / Double(max(second.count, 1))

        if secondAvg > firstAvg + 0.5 {
            insights.append("최근 무드가 이전보다 \(String(format: "%.1f", secondAvg - firstAvg))점 상승했습니다. 긍정적인 감정 변화를 유지하고 계세요! 🎉")
        } else if firstAvg > secondAvg + 0.5 {
            insights.append("최근 무드가 이전 대비 소폭 하락했습니다. 충분한 휴식과 나를 돌보는 시간이 필요할 수 있어요. 💙")
        } else {
            insights.append("감정 상태가 비교적 안정적으로 유지되고 있습니다. 균형 잡힌 감정 생활을 보내고 계시네요. 😌")
        }

        // 스트레스 관련
        let stressPts = emotionDataPoints(for: 5)
        let stressAvg = stressPts.map(\.value).reduce(0, +) / Double(max(stressPts.count, 1))
        if stressAvg > 6.5 {
            insights.append("스트레스 지수가 평균 \(String(format: "%.1f", stressAvg))로 높게 나타났습니다. 스트레스 해소 활동(운동, 명상, 취미 등)을 늘려보세요. 🧘")
        }

        // 기쁨 관련
        let joyPts = emotionDataPoints(for: 0)
        if let maxJoy = joyPts.max(by: { $0.value < $1.value }) {
            if maxJoy.value >= 8.0 {
                insights.append("\(maxJoy.label)에 기쁨 지수가 \(String(format: "%.1f", maxJoy.value))로 최고였습니다. 그날 무슨 일이 있었는지 기억하고 자주 되새겨 보세요. ✨")
            }
        }

        // 평온 vs 불안
        let serenityAvg = emotionDataPoints(for: 4).map(\.value).reduce(0, +) / Double(max(filteredEntries.count, 1))
        let anxietyAvg = emotionDataPoints(for: 3).map(\.value).reduce(0, +) / Double(max(filteredEntries.count, 1))
        if serenityAvg > anxietyAvg + 2 {
            insights.append("평온(평균 \(String(format: "%.1f", serenityAvg)))이 불안(평균 \(String(format: "%.1f", anxietyAvg)))보다 훨씬 높습니다. 내면의 안정감이 잘 유지되고 있어요. 🌿")
        }

        return insights
    }

    // MARK: - 트렌드 설명 텍스트
    private func trendDescription(for pts: [EmotionDataPoint], emotionDef: EmotionDefinition) -> String {
        guard pts.count >= 2 else { return "데이터가 부족합니다." }
        let values = pts.map(\.value)
        let avg = values.reduce(0, +) / Double(values.count)
        let max = values.max() ?? 0
        let min = values.min() ?? 0
        let trend = values.last! > values.first! ? "상승" : (values.last! < values.first! ? "하락" : "유지")
        let range = max - min

        var desc = "\(emotionDef.emoji) \(emotionDef.name)은 분석 기간 동안 평균 \(String(format: "%.1f", avg))점이었으며, "
        desc += "최고 \(String(format: "%.1f", max))점에서 최저 \(String(format: "%.1f", min))점 사이를 오갔습니다."
        if range > 4 {
            desc += " 변동 폭(\(String(format: "%.1f", range))점)이 큰 편으로, 상황에 따라 감정 변화가 두드러집니다."
        } else {
            desc += " 비교적 안정적인 수준으로 유지되고 있습니다."
        }
        desc += " 전반적으로 \(trend)하는 추세입니다."
        desc += " " + emotionDef.advice(for: avg)
        return desc
    }

    private func moodScoreColor(_ score: Double) -> Color {
        if score >= 7 { return .green }
        if score >= 4 { return .yellow }
        return .red
    }
}

// MARK: - 감정 정의 구조체
struct EmotionDefinition {
    let name: String
    let emoji: String
    let color: Color
    let description: String
    let adviceLow: String
    let adviceHigh: String

    func advice(for avg: Double) -> String {
        avg < 4 ? adviceLow : (avg > 7 ? adviceHigh : "")
    }
}

let emotionDefinitions: [EmotionDefinition] = [
    EmotionDefinition(
        name: "기쁨", emoji: "😊", color: .yellow,
        description: "즐거움, 행복, 만족감",
        adviceLow: "기쁠 일을 의도적으로 만들어보세요. 작은 즐거움이 하루를 바꿉니다.",
        adviceHigh: "기쁨이 넘치는 시간을 보내고 있네요. 그 에너지를 주변과 나눠보세요!"
    ),
    EmotionDefinition(
        name: "슬픔", emoji: "😢", color: .blue,
        description: "상실감, 외로움, 우울함",
        adviceLow: "슬픔도 자연스러운 감정입니다. 신뢰하는 사람과 마음을 나눠보세요.",
        adviceHigh: "슬픔 지수가 높습니다. 자기 돌봄과 전문적 도움을 고려해 보세요."
    ),
    EmotionDefinition(
        name: "분노", emoji: "😠", color: .red,
        description: "짜증, 화남, 불만",
        adviceLow: "분노를 적절히 표현하는 법을 연습하면 관계가 더 건강해집니다.",
        adviceHigh: "분노가 자주 느껴진다면 트리거가 무엇인지 일기에 적어보세요."
    ),
    EmotionDefinition(
        name: "불안", emoji: "😰", color: .orange,
        description: "걱정, 두려움, 긴장감",
        adviceLow: "불안은 미래를 통제하려는 신호입니다. 지금 이 순간에 집중해 보세요.",
        adviceHigh: "불안이 높습니다. 호흡 명상이나 규칙적인 루틴이 도움이 될 수 있어요."
    ),
    EmotionDefinition(
        name: "평온", emoji: "😌", color: .green,
        description: "안정감, 신뢰, 편안함",
        adviceLow: "평온함을 높이는 활동(자연 산책, 독서, 음악)을 늘려보세요.",
        adviceHigh: "내면의 평온이 잘 유지되고 있습니다. 이 상태를 소중히 하세요. 🌿"
    ),
    EmotionDefinition(
        name: "스트레스", emoji: "😫", color: .purple,
        description: "피로, 부담감, 압박",
        adviceLow: "스트레스를 건강하게 해소하는 나만의 방법을 찾아보세요.",
        adviceHigh: "스트레스가 누적되고 있습니다. 우선순위를 재조정하고 쉬어가는 게 필요해요."
    )
]

// MARK: - 미니 차트 카드 (2열 그리드용)
struct EmotionMiniChart: View {
    let title: String
    let emoji: String
    let color: Color
    let dataPoints: [EmotionDataPoint]
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(emoji).font(.system(size: 18))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                if let latest = dataPoints.last {
                    Text(String(format: "%.1f", latest.value))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(color)
                }
            }

            EmotionLineChart(
                dataPoints: dataPoints,
                color: color,
                title: title,
                showDots: false,
                height: 70,
                showGrid: false
            )
        }
        .padding(12)
        .background(isSelected ? color.opacity(0.12) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? color : Color.clear, lineWidth: 2)
        )
        .shadow(color: isSelected ? color.opacity(0.2) : .clear, radius: 6)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - 감정 바 차트 행
struct EmotionBarRow: View {
    let name: String
    let emoji: String
    let color: Color
    let value: Double
    let maxVal: Double

    @State private var animateBar = false

    var body: some View {
        HStack(spacing: 10) {
            Text(emoji).font(.system(size: 16))
            Text(name)
                .font(.system(size: 13))
                .frame(width: 48, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: animateBar ? geo.size.width * CGFloat(value / maxVal) : 0, height: 10)
                        .animation(.easeOut(duration: 0.8), value: animateBar)
                }
            }
            .frame(height: 10)
            Text(String(format: "%.1f", value))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
                .frame(width: 32, alignment: .trailing)
        }
        .onAppear { animateBar = true }
    }
}
