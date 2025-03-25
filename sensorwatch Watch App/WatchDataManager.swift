#if os(watchOS)
import Foundation
import CoreMotion

class WatchDataManager: ObservableObject {
    static let shared = WatchDataManager()
    
    private var motionManager = CMMotionManager()
    @Published var isRecording = false
    
    // 워치에서 직접 웹소켓 통신을 진행할 경우
    //private let serverURL = URL(string: "ws://192.168.45.34:5678")! //집
    private let serverURL = URL(string: "ws://192.168.0.213:5678")!  // 필요한 경우 주소 수정
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    
    // CoreMotion 타임스탬프 변환을 위한 변수들
    private var bootTimeInterval: TimeInterval = 0
    private var lastTimestamp: Date?
    private var sessionStartTime: Date?
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        urlSession = URLSession(configuration: configuration)
        
        // 시스템 부팅 시간 계산 (현재 시간 - systemUptime)
        bootTimeInterval = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    }
    
    func connect() {
        webSocketTask = urlSession.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        isRecording = true
        
        // 세션 시작 시간 기록
        sessionStartTime = Date()
        lastTimestamp = nil
        
        // 웹소켓 연결이 열리면 SESSION_START 메시지를 먼저 전송
        sendMessage("SESSION_START")
        startSensorUpdates()
        
        // 연결 유지를 위한 주기적 ping 설정
        schedulePing()
    }
    
    func disconnect() {
        // 센서 데이터 수집 종료 후 SESSION_END 메시지 송신
        stopSensorUpdates()
        sendMessage("SESSION_END")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isRecording = false
        
        // 세션 관련 변수 초기화
        sessionStartTime = nil
        lastTimestamp = nil
    }
    
    private func schedulePing() {
        guard isRecording else { return }
        
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                print("Ping 실패: \(error)")
            }
            
            // 10초마다 ping 전송
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                self?.schedulePing()
            }
        }
    }
    
    private func startSensorUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("DeviceMotion not available on watch.")
            return
        }
        
        // 60Hz로 설정 (16.67ms 간격)
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        
        // 전용 OperationQueue 생성
        let sensorQueue = OperationQueue()
        sensorQueue.maxConcurrentOperationCount = 1  // 순차 처리 보장
        sensorQueue.qualityOfService = .userInitiated
        
        // 모션 업데이트 시작
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: sensorQueue) { [weak self] motion, error in
            guard let self = self,
                  self.isRecording,
                  let motion = motion else {
                if let error = error {
                    print("모션 데이터 오류: \(error.localizedDescription)")
                }
                return
            }
            
            // CoreMotion의 timestamp를 실제 시간으로 변환
            // motion.timestamp는 기기 부팅 이후 경과 시간(초)
            // 실제 시간 = 부팅 시간 + timestamp
            let motionTimestamp = self.bootTimeInterval + motion.timestamp
            let sensorTimestamp = Date(timeIntervalSince1970: motionTimestamp)
            
            // 타임스탬프 정보를 디버깅창에 표시
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
            let formattedTimestamp = formatter.string(from: sensorTimestamp)
            print("⌚️ 워치 타임스탬프: \(formattedTimestamp) | CoreMotion timestamp: \(motion.timestamp)")
            
            // 중복 타임스탬프 방지 로직
            if let last = self.lastTimestamp, sensorTimestamp <= last {
                // 마지막 타임스탬프보다 작거나 같은 경우, 1ms 증가
                let adjustedTimestamp = last.addingTimeInterval(0.001)
                self.lastTimestamp = adjustedTimestamp
                
                // 디버그용 로그 (검증 후 제거 가능)
                print("⚠️ 타임스탬프 중복 감지! \(formattedTimestamp) → \(formatter.string(from: adjustedTimestamp))")
                
                // KST 타임스탬프 생성
                let formattedAdjustedTimestamp = formatter.string(from: adjustedTimestamp)
                
                // CSV 행 생성
                let csvRow = "\(formattedAdjustedTimestamp),\(motion.userAcceleration.x),\(motion.userAcceleration.y),\(motion.userAcceleration.z)," +
                             "\(motion.rotationRate.x),\(motion.rotationRate.y),\(motion.rotationRate.z)\n"
                
                // 메시지 전송
                DispatchQueue.main.async {
                    self.sendMessage(csvRow)
                }
            } else {
                // 정상적인 경우 (중복 없음)
                self.lastTimestamp = sensorTimestamp
                
                // KST 타임스탬프 생성
                let formattedTimestamp = formatter.string(from: sensorTimestamp)
                
                // CSV 행 생성
                let csvRow = "\(formattedTimestamp),\(motion.userAcceleration.x),\(motion.userAcceleration.y),\(motion.userAcceleration.z)," +
                             "\(motion.rotationRate.x),\(motion.rotationRate.y),\(motion.rotationRate.z)\n"
                
                // 메시지 전송
                DispatchQueue.main.async {
                    self.sendMessage(csvRow)
                }
            }
        }
    }
    
    private func stopSensorUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    func sendMessage(_ message: String) {
        guard let wsTask = webSocketTask, isRecording else {
            return
        }
        
        // 워치 데이터에는 "WATCH:" 접두어 추가
        let messageWithPrefix = "WATCH:" + message
        wsTask.send(.string(messageWithPrefix)) { error in
            if let error = error {
                print("메시지 전송 오류: \(error.localizedDescription)")
            }
        }
    }
}
#endif
