import Foundation
// CentralWebSocketManager.swift는 ../common 폴더에 위치합니다.
// 이 파일이 Xcode의 Build Phases → Compile Sources에 포함되어 있는지 확인하세요.

class RealTimeRecordingManager: NSObject, ObservableObject {
    static let shared = RealTimeRecordingManager()
    
    // 큐 분리: 워치와 DOT 데이터를 위한 별도 큐 생성
    private let watchSendQueue = DispatchQueue(label: "com.sensor.watchSendQueue", qos: .userInteractive)
    private let dotSendQueue = DispatchQueue(label: "com.sensor.dotSendQueue", qos: .userInitiated)
    private let controlSendQueue = DispatchQueue(label: "com.sensor.controlSendQueue", qos: .default)
    
    // 기존 통합 큐 (하위 호환성 유지)
    private let unifiedSendQueue = DispatchQueue(label: "com.sensor.unifiedSendQueue", qos: .userInteractive)
    
    // 큐 간 시간 간격 관리용 변수
    private var lastWatchSendTime: Date = Date()
    private var lastDotSendTime: Date = Date()
    private var lastUnifiedSendTime: Date = Date()
    
    // 최소 전송 간격(초) - 너무 빠른 전송으로 인한 충돌 방지
    private let watchMinSendInterval: TimeInterval = 0.003 // 3ms
    private let dotMinSendInterval: TimeInterval = 0.005   // 5ms
    private let unifiedMinSendInterval: TimeInterval = 0.005 // 기존과 동일
    
    private var webSocketTask: URLSessionWebSocketTask?
    private(set) var isConnected = false
    //private let serverURL = URL(string: "ws://192.168.45.34:5678")! //집
    private let serverURL = URL(string: "ws://192.168.0.213:5678")! //연구실
    private var session: URLSession!
    
    // 센서 데이터 큐: 연결 전에는 임시 저장 후 연결되면 전송
    private var pendingWatchMessages: [String] = []
    private var pendingDotMessages: [String] = []
    private var pendingControlMessages: [String] = []
    private var pendingMessages: [String] = [] // 기존 호환용
    
    // 버퍼 최대 크기
    private let maxBufferSize = 100
    
    override init() {
        super.init()
    }
    
    func connect() {
        CentralWebSocketManager.shared.connect()
    }
    
    func disconnect(completion: (() -> Void)? = nil) {
        CentralWebSocketManager.shared.send("SESSION_END")
        CentralWebSocketManager.shared.disconnect()
        completion?()
    }
    
    // 워치 데이터 전용 전송 메소드
    func sendWatchMessage(_ message: String) {
        CentralWebSocketManager.shared.send("W:" + message)
    }
    
    // DOT 데이터 전용 전송 메소드
    func sendDotMessage(_ message: String) {
        CentralWebSocketManager.shared.send("DOT:" + message)
    }
    
    // 컨트롤 메시지 전용 전송 메소드 (SESSION_START, SESSION_END 등)
    func sendControlMessage(_ message: String) {
        CentralWebSocketManager.shared.send(message)
    }
    
    // 기존 통합 전송 메소드 (하위 호환성 유지)
    func sendMessage(_ message: String) {
        CentralWebSocketManager.shared.send(message)
    }
    
    // 기존 센서 데이터 전송 메소드 유지
    func sendSensorData(_ data: SensorData) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: data.startTimestamp)
        let csvLine = "\(timestamp),\(data.accelerometer.x),\(data.accelerometer.y),\(data.accelerometer.z),\(data.gyroscope.x),\(data.gyroscope.y),\(data.gyroscope.z)"
        sendMessage(csvLine)
    }
    
    // 기존 메소드 유지
    func sendEulerAngles(timestamp: String, roll: Double, pitch: Double, yaw: Double) {
        let message = "EULER:\(roll),\(pitch),\(yaw)"
        sendMessage(message)
    }
    
    // 기존 메소드 유지
    func quaternionToEulerAngles(w: Double, x: Double, y: Double, z: Double) -> (roll: Double, pitch: Double, yaw: Double) {
        // 회전 행렬 요소 계산
        let sqw = w * w
        let sqx = x * x
        let sqy = y * y
        let sqz = z * z
        
        // 롤 (x-축 회전)
        let roll = atan2(2.0 * (w * x + y * z), sqw - sqx - sqy + sqz)
        
        // 피치 (y-축 회전)
        var pitch: Double
        let sinp = 2.0 * (w * y - z * x)
        if abs(sinp) >= 1 {
            pitch = sinp > 0 ? .pi / 2 : -.pi / 2 // 90도 또는 -90도
        } else {
            pitch = asin(sinp)
        }
        
        // 요 (z-축 회전)
        let yaw = atan2(2.0 * (w * z + x * y), sqw + sqx - sqy - sqz)
        
        // 라디안에서 각도로 변환
        let rollDeg = roll * (180.0 / .pi)
        let pitchDeg = pitch * (180.0 / .pi)
        let yawDeg = yaw * (180.0 / .pi)
        
        return (rollDeg, pitchDeg, yawDeg)
    }
    
    // 네트워크 모니터링 및 재연결 기능 추가
    private var reconnectTimer: Timer?
    private var isReconnecting = false
    private let maxReconnectAttempts = 5
    private var reconnectAttempts = 0
    
    func startReconnectMonitoring() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if !self.isConnected && !self.isReconnecting && self.reconnectAttempts < self.maxReconnectAttempts {
                self.tryReconnect()
            }
        }
    }
    
    private func tryReconnect() {
        isReconnecting = true
        reconnectAttempts += 1
        
        print("웹소켓 재연결 시도 \(reconnectAttempts)/\(maxReconnectAttempts)")
        
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        
        // 5초 후에 재연결 상태 확인
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            if !self.isConnected {
                print("웹소켓 재연결 실패")
                self.isReconnecting = false
            } else {
                print("웹소켓 재연결 성공")
                self.reconnectAttempts = 0
                self.isReconnecting = false
            }
        }
    }
}
