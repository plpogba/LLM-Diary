import SwiftUI

struct RadarChartView: View {
    var scores: EmotionScores
    var size: CGFloat = 260
    
    private let emotions = [
        "기쁨 (Joy)",
        "평온 (Serenity)",
        "스트레스 (Stress)",
        "슬픔 (Sadness)",
        "분노 (Anger)",
        "불안 (Anxiety)"
    ]
    
    private let emotionKeys: [KeyPath<EmotionScores, Double>] = [
        \.joy,
        \.serenity,
        \.stress,
        \.sadness,
        \.anger,
        \.anxiety
    ]
    
    var body: some View {
        VStack {
            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let maxRadius = min(geometry.size.width, geometry.size.height) / 2 * 0.72
                
                ZStack {
                    // 1. Grid Lines (Hexagons)
                    ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                        hexagonPath(center: center, radius: maxRadius * fraction)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    }
                    
                    // 2. Axis lines
                    ForEach(0..<6, id: \.self) { index in
                        let vertex = vertexPoint(index: index, center: center, radius: maxRadius)
                        Path { path in
                            path.move(to: center)
                            path.addLine(to: vertex)
                        }
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1.5)
                        
                        // Label placement
                        let labelOffset = labelOffsetPoint(index: index, center: center, radius: maxRadius)
                        Text(emotions[index])
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary.opacity(0.8))
                            .position(labelOffset)
                    }
                    
                    // 3. Emotion Polygon
                    if hasData {
                        emotionPolygon(center: center, radius: maxRadius)
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.accentColor.opacity(0.4),
                                        Color.purple.opacity(0.15)
                                    ]),
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: maxRadius
                                )
                            )
                        
                        emotionPolygon(center: center, radius: maxRadius)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.accentColor, .purple]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 2.5
                            )
                        
                        // Small dots on the vertices of the emotion polygon
                        ForEach(0..<6, id: \.self) { index in
                            let val = scores[keyPath: emotionKeys[index]]
                            let pt = vertexPoint(index: index, center: center, radius: maxRadius * CGFloat(val / 10.0))
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                                .shadow(radius: 2)
                                .position(pt)
                        }
                    } else {
                        // Empty State Label
                        Text("감정 데이터 없음")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: size, height: size)
            
            // Value display legend
            HStack(spacing: 12) {
                legendItem(title: "😊 기쁨", score: scores.joy, color: .orange)
                legendItem(title: "😌 평온", score: scores.serenity, color: .green)
                legendItem(title: "😫 피로", score: scores.stress, color: .gray)
            }
            .padding(.top, 8)
            
            HStack(spacing: 12) {
                legendItem(title: "😭 슬픔", score: scores.sadness, color: .blue)
                legendItem(title: "😡 분노", score: scores.anger, color: .red)
                legendItem(title: "😨 불안", score: scores.anxiety, color: .purple)
            }
            .padding(.top, 2)
        }
    }
    
    private var hasData: Bool {
        scores.joy > 0 || scores.sadness > 0 || scores.anger > 0 || scores.anxiety > 0 || scores.serenity > 0 || scores.stress > 0
    }
    
    // Calculates a vertex on the hexagon
    private func vertexPoint(index: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        // Offset by -90 deg (pi/2) to make the first point at the top
        let angle = -Double.pi / 2.0 + (Double(index) * Double.pi / 3.0)
        let x = center.x + radius * CGFloat(cos(angle))
        let y = center.y + radius * CGFloat(sin(angle))
        return CGPoint(x: x, y: y)
    }
    
    // Custom offsets for labels so they don't overlap with vertices
    private func labelOffsetPoint(index: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2.0 + (Double(index) * Double.pi / 3.0)
        let extraDistance: CGFloat = 20.0
        let x = center.x + (radius + extraDistance) * CGFloat(cos(angle))
        let y = center.y + (radius + extraDistance) * CGFloat(sin(angle))
        return CGPoint(x: x, y: y)
    }
    
    // Hexagon drawing path
    private func hexagonPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for index in 0..<6 {
            let vertex = vertexPoint(index: index, center: center, radius: radius)
            if index == 0 {
                path.move(to: vertex)
            } else {
                path.addLine(to: vertex)
            }
        }
        path.closeSubpath()
        return path
    }
    
    // Polygon of user's scores
    private func emotionPolygon(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for index in 0..<6 {
            let score = scores[keyPath: emotionKeys[index]]
            let scaledRadius = radius * CGFloat(score / 10.0)
            let vertex = vertexPoint(index: index, center: center, radius: scaledRadius)
            if index == 0 {
                path.move(to: vertex)
            } else {
                path.addLine(to: vertex)
            }
        }
        path.closeSubpath()
        return path
    }
    
    private func legendItem(title: String, score: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(title):")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.1f", score))
                .font(.caption.bold())
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }
}

#Preview {
    RadarChartView(scores: EmotionScores(
        joy: 8.0,
        sadness: 2.0,
        anger: 0.5,
        anxiety: 3.0,
        serenity: 7.0,
        stress: 4.5
    ))
    .padding()
}
