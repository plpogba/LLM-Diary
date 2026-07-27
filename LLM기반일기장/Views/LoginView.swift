import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: BiometricAuthManager
    @State private var animateIcon = false
    
    var body: some View {
        ZStack {
            // Premium background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.12, blue: 0.2),
                    Color(red: 0.05, green: 0.05, blue: 0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Subtle glowing background circles
            VStack {
                HStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 300, height: 300)
                        .blur(radius: 80)
                        .offset(x: -50, y: -50)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 300, height: 300)
                        .blur(radius: 80)
                        .offset(x: 50, y: 50)
                }
            }
            .ignoresSafeArea()
            
            // Login Card
            VStack(spacing: 30) {
                Spacer()
                
                // Icon Header
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "sparkles.bubble.fill")
                        .font(.system(size: 45))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.accentColor, .purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(animateIcon ? 1.05 : 0.95)
                        .animation(
                            .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                            value: animateIcon
                        )
                }
                .onAppear {
                    animateIcon = true
                }
                
                // Titles
                VStack(spacing: 8) {
                    Text("AI 실시간 대화 일기장")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("AI와 대화하며 자연스럽게 완성하는 비밀 감정 일기장")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                // Biometrics Unlock Button
                VStack(spacing: 16) {
                    Button(action: {
                        authManager.authenticate()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: authManager.isBiometricsAvailable ? "touchid" : "lock.open.fill")
                                .font(.title2)
                            Text("생체인증으로 일기장 열기")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .frame(maxWidth: 320)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.accentColor, .purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    
                    // Fallback option (Simulate login)
                    Button(action: {
                        authManager.simulateLoginSuccess()
                    }) {
                        Text("개발자/시뮬레이터용 바로 입장")
                            .font(.footnote)
                            .foregroundColor(.accentColor.opacity(0.8))
                            .underline()
                    }
                    .padding(.top, 8)
                }
                
                // Error display
                if let error = authManager.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal, 24)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                
                Spacer()
                
                // Footer
                Text("Protected by Apple LocalAuthentication & Gemini AI")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.bottom, 20)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.white.opacity(0.04))
                    .background(VisualEffectView().opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 450, maxHeight: 580)
            .padding()
        }
    }
}

// Helper view for macOS blur and iOS compatibility
#if os(macOS)
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#else
struct VisualEffectView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
#endif

#Preview {
    LoginView()
        .environmentObject(BiometricAuthManager())
}
