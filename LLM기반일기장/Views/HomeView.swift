import SwiftUI

struct HomeView: View {
    @EnvironmentObject var diaryStore: DiaryStore
    
    @State private var searchText = ""
    @State private var selectedPeriod = 0 // 0: 전체, 1: 1주일, 2: 1개월
    @State private var selectedKeyword: String? = nil
    
    @State private var isShowingWriter = false
    @State private var selectedEntry: DiaryEntry? = nil
    @State private var selectedDetailImage: NSImage? = nil
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar / Content layout
            VStack(spacing: 0) {
                // Search Bar & Filter Headers
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("일기 내용, 제목, 키워드 검색...", text: $searchText)
                            .textFieldStyle(.plain)
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    
                    // Period Picker
                    Picker("기간 선택", selection: $selectedPeriod) {
                        Text("전체").tag(0)
                        Text("최근 7일").tag(1)
                        Text("최근 30일").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                
                // Active Filters Indicator
                if selectedKeyword != nil || selectedPeriod != 0 || !searchText.isEmpty {
                    HStack {
                        Text("필터 적용 중:")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        
                        if let keyword = selectedKeyword {
                            filterTag(text: "#\(keyword)") {
                                selectedKeyword = nil
                            }
                        }
                        if selectedPeriod != 0 {
                            filterTag(text: selectedPeriod == 1 ? "최근 7일" : "최근 30일") {
                                selectedPeriod = 0
                            }
                        }
                        if !searchText.isEmpty {
                            filterTag(text: "검색어: \(searchText)") {
                                searchText = ""
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
                
                // Timeline list
                if filteredEntries.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "book.closed")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("저장된 일기가 없습니다.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("오른쪽 위의 + 버튼을 눌러 첫 일기를 작성해보세요!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(groupedEntriesKeys, id: \.self) { dateString in
                            Section(header: Text(dateString).font(.subheadline.bold()).foregroundColor(.secondary)) {
                                ForEach(groupedEntries[dateString] ?? []) { entry in
                                    DiaryRow(entry: entry, isSelected: selectedEntry?.id == entry.id)
                                        .onTapGesture {
                                            selectedEntry = entry
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                diaryStore.delete(entry)
                                                if selectedEntry?.id == entry.id {
                                                    selectedEntry = nil
                                                }
                                            } label: {
                                                Label("삭제", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 280, maxWidth: 360)
            
            Divider()
            
            // Detail Pane & Emotion Graph
            if let entry = selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Title / Header
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(formatDate(entry.date))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text(entry.title)
                                    .font(.title2.bold())
                                    .foregroundColor(.primary)
                            }
                            Spacer()
                            Text(entry.moodEmoji)
                                .font(.system(size: 40))
                        }
                        .padding(.bottom, 10)
                        
                        // Keywords tags
                        HStack(spacing: 8) {
                            ForEach(entry.keywords, id: \.self) { tag in
                                Button(action: {
                                    selectedKeyword = tag
                                }) {
                                    Text("#\(tag)")
                                        .font(.caption.bold())
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Divider()
                        
                        // Radar chart for this entry
                        VStack(alignment: .leading, spacing: 8) {
                            Text("이날의 감정 상태")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            RadarChartView(scores: entry.emotionScores, size: 200)
                                .padding()
                                .background(Color.secondary.opacity(0.04))
                                .cornerRadius(12)
                        }
                        
                        Divider()
                        
                        // Attached Photos Gallery
                        if !entry.images.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "photo.stack.fill")
                                        .foregroundColor(.accentColor)
                                    Text("첨부된 사진 (\(entry.images.count)장)")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(entry.images, id: \.self) { filename in
                                            if let image = ImageFileManager.shared.loadImage(filename: filename) {
                                                Image(nsImage: image)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 140, height: 100)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                                    )
                                                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                                                    .onTapGesture {
                                                        selectedDetailImage = image
                                                    }
                                                    .help("클릭하여 사진 확대")
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            
                            Divider()
                        }
                        
                        // Main content
                        VStack(alignment: .leading, spacing: 8) {
                            Text("일기 본문")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text(entry.content)
                                .font(.body)
                                .lineSpacing(6)
                                .foregroundColor(.primary)
                                .padding(12)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // Chat Log option (if exists)
                        if !entry.chatHistory.isEmpty {
                            Divider()
                            
                            DisclosureGroup("AI 비서와 주고받은 대화 보기") {
                                VStack(spacing: 12) {
                                    ForEach(entry.chatHistory) { msg in
                                        HStack {
                                            if msg.isUser {
                                                Spacer()
                                                Text(msg.text)
                                                    .font(.caption)
                                                    .padding(8)
                                                    .background(Color.accentColor.opacity(0.8))
                                                    .foregroundColor(.white)
                                                    .cornerRadius(8)
                                            } else {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("AI 비서")
                                                        .font(.system(size: 9).bold())
                                                        .foregroundColor(.accentColor)
                                                    Text(msg.text)
                                                        .font(.caption)
                                                        .padding(8)
                                                        .background(Color.secondary.opacity(0.1))
                                                        .cornerRadius(8)
                                                }
                                                Spacer()
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 10)
                            }
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity)
            } else {
                // Empty Details: Show summary chart + trend widget
                ScrollView {
                    VStack(spacing: 24) {
                        // 종합 레이더 차트
                        VStack(spacing: 8) {
                            Text("📊 기간별 평균 감정 그래프")
                                .font(.headline)
                            Text(selectedPeriodDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        RadarChartView(scores: averageScores, size: 200)
                            .padding()
                            .background(Color.secondary.opacity(0.04))
                            .cornerRadius(20)

                        Divider().padding(.horizontal, 40)

                        // 미니 무드 트렌드 차트
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("종합 무드 트렌드", systemImage: "chart.line.uptrend.xyaxis")
                                    .font(.subheadline.bold())
                                Spacer()
                                if let latest = homeMoodPoints.last {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(homeMoodColor(latest.value))
                                            .frame(width: 8, height: 8)
                                        Text(String(format: "최근 %.1f", latest.value))
                                            .font(.caption.bold())
                                            .foregroundColor(homeMoodColor(latest.value))
                                    }
                                }
                            }

                            if homeMoodPoints.count < 2 {
                                Text("일기를 2개 이상 작성하면 무드 그래프가 나타납니다")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .frame(height: 80)
                            } else {
                                EmotionLineChart(
                                    dataPoints: homeMoodPoints,
                                    color: .accentColor,
                                    title: "무드",
                                    showDots: true,
                                    height: 120
                                )
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(14)
                        .padding(.horizontal, 20)

                        Divider().padding(.horizontal, 40)

                        // Tag Dashboard Cloud
                        VStack(alignment: .leading, spacing: 12) {
                            Text("인기 키워드로 일기 찾기")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            FlowLayout(items: allKeywords) { tag in
                                Button(action: {
                                    selectedKeyword = tag
                                }) {
                                    Text("#\(tag)")
                                        .font(.subheadline)
                                        .foregroundColor(selectedKeyword == tag ? .white : .accentColor)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedKeyword == tag ? Color.accentColor : Color.accentColor.opacity(0.1))
                                        .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal)
                        }
                        .frame(maxWidth: 450)

                        Spacer(minLength: 20)
                    }
                    .padding(.vertical, 20)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("일기 목록")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    isShowingWriter = true
                }) {
                    Label("새 일기", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingWriter) {
            NewDiaryView()
        }
        .sheet(item: Binding(get: {
            selectedDetailImage.map { IdentifiableImage(image: $0) }
        }, set: {
            selectedDetailImage = $0?.image
        })) { item in
            ImageViewerModal(image: item.image) {
                selectedDetailImage = nil
            }
        }
        .onAppear {
            if selectedEntry == nil && !filteredEntries.isEmpty {
                // Keep details empty to show summary chart by default
            }
        }
    }
    
    // MARK: - Filter logic
    
    private var filteredEntries: [DiaryEntry] {
        let calendar = Calendar.current
        let now = Date()
        
        return diaryStore.entries.filter { entry in
            // 1. Text Search Filter
            if !searchText.isEmpty {
                let textMatch = entry.title.localizedCaseInsensitiveContains(searchText) ||
                               entry.content.localizedCaseInsensitiveContains(searchText)
                let keywordMatch = entry.keywords.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
                guard textMatch || keywordMatch else { return false }
            }
            
            // 2. Keyword Tag Filter
            if let keyword = selectedKeyword {
                guard entry.keywords.contains(keyword) else { return false }
            }
            
            // 3. Period Date Filter
            if selectedPeriod == 1 { // 1주일
                guard let lastWeek = calendar.date(byAdding: .day, value: -7, to: now),
                      entry.date >= lastWeek else { return false }
            } else if selectedPeriod == 2 { // 1개월
                guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now),
                      entry.date >= lastMonth else { return false }
            }
            
            return true
        }
    }
    
    // Helper to calculate summary period text
    private var selectedPeriodDescription: String {
        let count = filteredEntries.count
        let periodName = selectedPeriod == 0 ? "전체 기간" : (selectedPeriod == 1 ? "최근 7일" : "최근 30일")
        let keywordName = selectedKeyword != nil ? " ('#\(selectedKeyword!)' 필터 적용됨)" : ""
        return "\(periodName) 동안 작성된 \(count)개의 일기를 기반으로 한 분석 그래프입니다.\(keywordName)"
    }
    
    // Grouping entries by Month-Year for Timeline headers
    private var groupedEntries: [String: [DiaryEntry]] {
        Dictionary(grouping: filteredEntries) { entry in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy년 MM월"
            return formatter.string(from: entry.date)
        }
    }
    
    private var groupedEntriesKeys: [String] {
        groupedEntries.keys.sorted(by: >)
    }
    
    // Average scores calculations
    private var averageScores: EmotionScores {
        let filtered = filteredEntries
        guard !filtered.isEmpty else { return .empty }
        
        var totalJoy = 0.0
        var totalSadness = 0.0
        var totalAnger = 0.0
        var totalAnxiety = 0.0
        var totalSerenity = 0.0
        var totalStress = 0.0
        
        for entry in filtered {
            totalJoy += entry.emotionScores.joy
            totalSadness += entry.emotionScores.sadness
            totalAnger += entry.emotionScores.anger
            totalAnxiety += entry.emotionScores.anxiety
            totalSerenity += entry.emotionScores.serenity
            totalStress += entry.emotionScores.stress
        }
        
        let count = Double(filtered.count)
        return EmotionScores(
            joy: totalJoy / count,
            sadness: totalSadness / count,
            anger: totalAnger / count,
            anxiety: totalAnxiety / count,
            serenity: totalSerenity / count,
            stress: totalStress / count
        )
    }
    
    // Helper: Home mood data points (date-sorted all entries)
    private var homeMoodPoints: [EmotionDataPoint] {
        filteredEntries.sorted { $0.date < $1.date }.map { entry in
            EmotionDataPoint(
                date: entry.date,
                value: entry.emotionScores.moodScore,
                emoji: entry.moodEmoji,
                label: entry.date.shortLabel()
            )
        }
    }

    private func homeMoodColor(_ score: Double) -> Color {
        if score >= 7 { return .green }
        if score >= 4 { return .yellow }
        return .red
    }

    // Gather all keywords present in database for the tag cloud
    private var allKeywords: [String] {
        let all = diaryStore.entries.flatMap { $0.keywords }
        let frequency = all.reduce(into: [:]) { counts, word in counts[word, default: 0] += 1 }
        // Sort keywords by frequency of usage
        return frequency.sorted { $0.value > $1.value }.map { $0.key }
    }
    
    // Date formatting helper
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy년 MM월 dd일 (E)"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
    
    // UI Helpers
    private func filterTag(text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.15))
        .foregroundColor(.accentColor)
        .cornerRadius(8)
    }
}

// Row component for the left list
struct DiaryRow: View {
    var entry: DiaryEntry
    var isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Text(entry.moodEmoji)
                .font(.system(size: 28))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.body.bold())
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .primary)
                
                HStack {
                    Text(shortDate(entry.date))
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    
                    if !entry.images.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 9))
                            if entry.images.count > 1 {
                                Text("\(entry.images.count)")
                                    .font(.system(size: 9).bold())
                            }
                        }
                        .foregroundColor(isSelected ? .white.opacity(0.85) : .accentColor)
                    }
                    
                    Spacer()
                    
                    Text(entry.keywords.prefix(2).map { "#\($0)" }.joined(separator: " "))
                        .font(.caption2.bold())
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .accentColor)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
    
    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM월 dd일"
        return formatter.string(from: date)
    }
}

// FlowLayout for tag clouds (since SwiftUI doesn't have an out-of-the-box wrap layout)
struct FlowLayout: View {
    let items: [String]
    let content: (String) -> AnyView
    
    init<V: View>(items: [String], @ViewBuilder content: @escaping (String) -> V) {
        self.items = items
        self.content = { AnyView(content($0)) }
    }
    
    @State private var totalHeight = CGFloat.zero
    
    var body: some View {
        VStack {
            GeometryReader { geometry in
                self.generateContent(in: geometry)
            }
        }
        .frame(height: totalHeight)
    }
    
    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        
        return ZStack(alignment: .topLeading) {
            ForEach(self.items, id: \.self) { item in
                self.content(item)
                    .padding([.horizontal, .vertical], 4)
                    .alignmentGuide(.leading, computeValue: { d in
                        if (abs(width - d.width) > g.size.width) {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        if item == self.items.last! {
                            width = 0 // last item
                        } else {
                            width -= d.width
                        }
                        return result
                    })
                    .alignmentGuide(.top, computeValue: { d in
                        let result = height
                        if item == self.items.last! {
                            height = 0 // last item
                        }
                        return result
                    })
            }
        }
        .background(viewHeightReader($totalHeight))
    }
    
    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        return GeometryReader { geo -> Color in
            let rect = geo.frame(in: .local)
            DispatchQueue.main.async {
                binding.wrappedValue = rect.size.height
            }
            return .clear
        }
    }
}
