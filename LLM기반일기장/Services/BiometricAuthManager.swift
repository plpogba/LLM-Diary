import Foundation
import LocalAuthentication
import Combine

class BiometricAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isBiometricsAvailable = false
    @Published var authError: String? = nil
    
    init() {
        checkBiometricAvailability()
    }
    
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        
        // Check if biometric login is available on this device
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        DispatchQueue.main.async {
            self.isBiometricsAvailable = available
            if let error = error {
                print("Biometric availability error: \(error.localizedDescription)")
            }
        }
    }
    
    func authenticate(completion: @escaping (Bool) -> Void = { _ in }) {
        let context = LAContext()
        var error: NSError?
        
        let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
        
        if context.canEvaluatePolicy(policy, error: &error) {
            let reason = "생체 인증을 통해 일기장에 로그인합니다."
            
            context.evaluatePolicy(policy, localizedReason: reason) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        self.isAuthenticated = true
                        self.authError = nil
                        completion(true)
                    } else {
                        if let error = authError as? LAError {
                            switch error.code {
                            case .userCancel:
                                self.authError = "사용자가 인증을 취소했습니다."
                            case .userFallback:
                                self.authError = "비밀번호 입력을 선택했습니다."
                            case .biometryNotAvailable:
                                self.authError = "생체 인증 장치가 비활성화 상태입니다."
                            case .biometryNotEnrolled:
                                self.authError = "등록된 생체 인증 정보가 없습니다."
                            default:
                                self.authError = error.localizedDescription
                            }
                        } else {
                            self.authError = authError?.localizedDescription ?? "알 수 없는 에러가 발생했습니다."
                        }
                        completion(false)
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                let errorDesc = error?.localizedDescription ?? "생체 인증을 사용할 수 없는 환경입니다."
                self.authError = errorDesc
                self.isBiometricsAvailable = false
                completion(false)
            }
        }
    }
    
    func simulateLoginSuccess() {
        DispatchQueue.main.async {
            self.isAuthenticated = true
            self.authError = nil
        }
    }
    
    func logout() {
        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.authError = nil
        }
    }
}
