import SwiftUI

// MARK: - 감정 데이터 포인트
struct EmotionDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double   // 0 ~ 10
    let emoji: String
    let label: String   // 날짜 라벨
}

// MARK: - 단일 라인 곡선 차트
struct EmotionLineChart: View {
    let dataPoints: [EmotionDataPoint]
    let color: Color
    let title: String
    let showDots: Bool
    let height: CGFloat
    var showGrid: Bool = true
    var minVal: Double = 0
    var maxVal: Double = 10

    @State private var hoveredIndex: Int? = nil
    @State private var animateChart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if dataPoints.count < 2 {
                VStack {
                    Spacer()
                    Text("일기를 2개 이상 작성하면 그래프가 나타납니다")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: height)
            } else {
                GeometryReader { geo in
                    ZStack {
                        // 배경 그리드
                        if showGrid {
                            gridLines(in: geo.size)
                        }

                        // 채워진 영역 (그라디언트)
                        filledArea(in: geo.size)

                        // 곡선 라인
                        curvePath(in: geo.size)
                            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .scaleEffect(x: animateChart ? 1 : 0, anchor: .leading)
                            .animation(.easeInOut(duration: 1.0), value: animateChart)

                        // 데이터 포인트 원
                        if showDots {
                            ForEach(Array(dataPoints.enumerated()), id: \.element.id) { idx, point in
                                let pos = position(for: idx, in: geo.size)
                                ZStack {
                                    Circle()
                                        .fill(color)
                                        .frame(width: hoveredIndex == idx ? 12 : 8,
                                               height: hoveredIndex == idx ? 12 : 8)
                                    Circle()
                                        .fill(Color(NSColor.windowBackgroundColor))
                                        .frame(width: hoveredIndex == idx ? 6 : 4,
                                               height: hoveredIndex == idx ? 6 : 4)
                                }
                                .position(pos)
                                .animation(.spring(response: 0.2), value: hoveredIndex)
                                .onHover { inside in
                                    hoveredIndex = inside ? idx : nil
                                }
                            }
                        }

                        // 호버 팝오버
                        if let hIdx = hoveredIndex, hIdx < dataPoints.count {
                            let point = dataPoints[hIdx]
                            let pos = position(for: hIdx, in: geo.size)
                            VStack(spacing: 2) {
                                Text(point.emoji)
                                    .font(.system(size: 18))
                                Text(String(format: "%.1f", point.value))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(color)
                                Text(point.label)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.windowBackgroundColor))
                                    .shadow(color: .black.opacity(0.15), radius: 6)
                            )
                            .position(x: min(max(pos.x, 60), geo.size.width - 60),
                                      y: max(pos.y - 54, 40))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                }
                .frame(height: height)
                .clipped()
                .onAppear { animateChart = true }
            }

            // X축 날짜 라벨
            if dataPoints.count >= 2 {
                xAxisLabels
            }
        }
    }

    // MARK: - 베지어 곡선 경로
    private func curvePath(in size: CGSize) -> Path {
        guard dataPoints.count >= 2 else { return Path() }
        var path = Path()
        let pts = dataPoints.enumerated().map { position(for: $0.offset, in: size) }
        path.move(to: pts[0])
        for i in 1..<pts.count {
            let prev = pts[i - 1]
            let curr = pts[i]
            let cp1 = CGPoint(x: prev.x + (curr.x - prev.x) * 0.5, y: prev.y)
            let cp2 = CGPoint(x: curr.x - (curr.x - prev.x) * 0.5, y: curr.y)
            path.addCurve(to: curr, control1: cp1, control2: cp2)
        }
        return path
    }

    // MARK: - 그라디언트 채우기
    private func filledArea(in size: CGSize) -> some View {
        guard dataPoints.count >= 2 else { return AnyView(EmptyView()) }
        let pts = dataPoints.enumerated().map { position(for: $0.offset, in: size) }
        var path = Path()
        path.move(to: CGPoint(x: pts[0].x, y: size.height))
        path.addLine(to: pts[0])
        for i in 1..<pts.count {
            let prev = pts[i - 1]
            let curr = pts[i]
            let cp1 = CGPoint(x: prev.x + (curr.x - prev.x) * 0.5, y: prev.y)
            let cp2 = CGPoint(x: curr.x - (curr.x - prev.x) * 0.5, y: curr.y)
            path.addCurve(to: curr, control1: cp1, control2: cp2)
        }
        path.addLine(to: CGPoint(x: pts.last!.x, y: size.height))
        path.closeSubpath()

        return AnyView(
            path.fill(
                LinearGradient(
                    gradient: Gradient(colors: [color.opacity(0.25), color.opacity(0.02)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        )
    }

    // MARK: - 그리드 라인
    private func gridLines(in size: CGSize) -> some View {
        let steps = [0.0, 2.5, 5.0, 7.5, 10.0]
        return ZStack {
            ForEach(steps, id: \.self) { val in
                let y = size.height - CGFloat((val - minVal) / (maxVal - minVal)) * size.height
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(Color.secondary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    // MARK: - X축 라벨
    private var xAxisLabels: some View {
        GeometryReader { geo in
            ForEach(Array(dataPoints.enumerated()), id: \.element.id) { idx, pt in
                // 처음, 마지막, 그리고 중간 라벨만
                if idx == 0 || idx == dataPoints.count - 1 || (dataPoints.count > 4 && idx == dataPoints.count / 2) {
                    let x = xPos(for: idx, width: geo.size.width)
                    Text(pt.label)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .position(x: x, y: 8)
                }
            }
        }
        .frame(height: 18)
    }

    // MARK: - 위치 계산 도우미
    private func position(for index: Int, in size: CGSize) -> CGPoint {
        let x = xPos(for: index, width: size.width)
        let normalised = (dataPoints[index].value - minVal) / (maxVal - minVal)
        let y = size.height - CGFloat(normalised) * size.height * 0.9 - size.height * 0.05
        return CGPoint(x: x, y: y)
    }

    private func xPos(for index: Int, width: CGFloat) -> CGFloat {
        guard dataPoints.count > 1 else { return width / 2 }
        let spacing = width / CGFloat(dataPoints.count - 1)
        return CGFloat(index) * spacing
    }
}

// MARK: - 날짜 포맷 헬퍼
extension Date {
    func shortLabel() -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: self)
    }
}
