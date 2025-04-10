import Foundation

class RealTimeRecordingManager: NSObject, URLSessionWebSocketDelegate, ObservableObject {
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
    private let serverURL = URL(string: "ws://192.168.0.213:5678")!
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
        // delegateQueue를 메인 큐로 지정하여 delegate 콜백이 메인 스레드에서 호출되도록 함
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
    }
    
    func connect() {
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        // 연결이 열릴 때까지 잠시 대기하는 로직은 delegate에서 처리됨
    }
    
    func disconnect(completion: (() -> Void)? = nil) {
        sendControlMessage("SESSION_END")  // 세션 종료 메시지 전송
        
        // 보류 메시지 모두 제거
        pendingWatchMessages.removeAll()
        pendingDotMessages.removeAll()
        pendingControlMessages.removeAll()
        pendingMessages.removeAll()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self.isConnected = false
            print("WebSocket 연결이 종료됨")
            completion?()
        }
    }
    
    // 워치 데이터 전용 전송 메소드
    func sendWatchMessage(_ message: String) {
        watchSendQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 연결 없을 경우 버퍼에 저장 (최대 크기 제한)
            if !self.isConnected {
                if self.pendingWatchMessages.count < self.maxBufferSize {
                    self.pendingWatchMessages.append(message)
                } else {
                    // 버퍼 가득 찬 경우 가장 오래된 메시지 제거 후 신규 추가
                    self.pendingWatchMessages.removeFirst()
                    self.pendingWatchMessages.append(message)
                }
                return
            }
            
            // 전송 간격 제어 - 너무 빠른 메시지 방지
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastWatchSendTime)
            if elapsed < self.watchMinSendInterval {
                Thread.sleep(forTimeInterval: self.watchMinSendInterval - elapsed)
            }
            
            // 메시지 전송
            let wsMessage = URLSessionWebSocketTask.Message.string(message)
            self.webSocketTask?.send(wsMessage) { error in
                if let error = error {
                    print("워치 데이터 전송 오류: \(error.localizedDescription)")
                }
            }
            
            self.lastWatchSendTime = Date()
        }
    }
    
    // DOT 데이터 전용 전송 메소드
    func sendDotMessage(_ message: String) {
        dotSendQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 연결 없을 경우 버퍼에 저장 (최대 크기 제한)
            if !self.isConnected {
                if self.pendingDotMessages.count < self.maxBufferSize {
                    self.pendingDotMessages.append(message)
                } else {
                    // 버퍼 가득 찬 경우 가장 오래된 메시지 제거 후 신규 추가
                    self.pendingDotMessages.removeFirst()
                    self.pendingDotMessages.append(message)
                }
                return
            }
            
            // 전송 간격 제어 - 너무 빠른 메시지 방지
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastDotSendTime)
            if elapsed < self.dotMinSendInterval {
                Thread.sleep(forTimeInterval: self.dotMinSendInterval - elapsed)
            }
            
            // 메시지 전송
            let wsMessage = URLSessionWebSocketTask.Message.string(message)
            self.webSocketTask?.send(wsMessage) { error in
                if let error = error {
                    print("DOT 데이터 전송 오류: \(error.localizedDescription)")
                }
            }
            
            self.lastDotSendTime = Date()
        }
    }
    
    // 컨트롤 메시지 전용 전송 메소드 (SESSION_START, SESSION_END 등)
    func sendControlMessage(_ message: String) {
        controlSendQueue.async { [weak self] in
            guard let self = self else { return }
            
            if !self.isConnected {
                self.pendingControlMessages.append(message)
                return
            }
            
            let wsMessage = URLSessionWebSocketTask.Message.string(message)
            self.webSocketTask?.send(wsMessage) { error in
                if let error = error {
                    print("컨트롤 메시지 전송 오류: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 기존 통합 전송 메소드 (하위 호환성 유지)
    func sendMessage(_ message: String) {
        // 메시지 타입에 따라 적절한 큐로 라우팅
        if message.hasPrefix("W:") {
            // 워치 데이터 (Yaw만 포함)
            sendWatchMessage(message)
        } else if message.hasPrefix("DOT:") || message.hasPrefix("D:") {
            // DOT 데이터 (Roll만 포함)
            sendDotMessage(message)
        } else if message == "SESSION_START" || message == "SESSION_END" {
            sendControlMessage(message)
        } else {
            // 타입 구분 불가능한 메시지는 기존 통합 큐 사용
            unifiedSendQueue.async { [weak self] in
                guard let self = self else { return }
                
                if !self.isConnected {
                    self.pendingMessages.append(message)
                    return
                }
                
                // 기존 전송 간격 제어 유지
                let now = Date()
                let elapsed = now.timeIntervalSince(self.lastUnifiedSendTime)
                if elapsed < self.unifiedMinSendInterval {
                    Thread.sleep(forTimeInterval: self.unifiedMinSendInterval - elapsed)
                }
                
                let wsMessage = URLSessionWebSocketTask.Message.string(message)
                self.webSocketTask?.send(wsMessage) { error in
                    if let error = error {
                        print("통합 메시지 전송 오류: \(error.localizedDescription)")
                    }
                }
                
                self.lastUnifiedSendTime = Date()
            }
        }
    }
    
    // 웹소켓 연결 성공 시 - 보류된 메시지 처리
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        isConnected = true
        print("WebSocket 연결 성공")
        
        // SESSION_START 메시지 먼저 전송
        sendControlMessage("SESSION_START")
        
        // 보류된 메시지 전송 - 먼저 컨트롤 메시지, 그다음 워치와 DOT 메시지 번갈아가며 전송
        processPendingMessages()
        
        // 이후 계속 수신
        receiveMessages()
    }
    
    // 보류된 메시지 순차 처리 (컨트롤 → 워치/DOT 번갈아가며)
    private func processPendingMessages() {
        // 1. 컨트롤 메시지 먼저 처리
        for message in pendingControlMessages {
            sendControlMessage(message)
        }
        pendingControlMessages.removeAll()
        
        // 2. 기존 통합 메시지 처리 (하위 호환용)
        for message in pendingMessages {
            sendMessage(message)
        }
        pendingMessages.removeAll()
        
        // 3. 워치/DOT 메시지 번갈아가며 처리 (최대 처리량 제한)
        if !pendingWatchMessages.isEmpty || !pendingDotMessages.isEmpty {
            processWatchAndDotMessages()
        }
    }
    
    // 워치와 DOT 메시지 번갈아가며 일괄 처리
    private func processWatchAndDotMessages(maxBatch: Int = 20) {
        var watchProcessed = 0
        var dotProcessed = 0
        
        // 워치와 DOT 메시지를 번갈아가며 처리
        while (!pendingWatchMessages.isEmpty || !pendingDotMessages.isEmpty) &&
              (watchProcessed + dotProcessed < maxBatch) {
            
            // 워치 메시지 처리
            if !pendingWatchMessages.isEmpty {
                let message = pendingWatchMessages.removeFirst()
                sendWatchMessage(message)
                watchProcessed += 1
            }
            
            // DOT 메시지 처리
            if !pendingDotMessages.isEmpty {
                let message = pendingDotMessages.removeFirst()
                sendDotMessage(message)
                dotProcessed += 1
            }
        }
        
        // 아직 남은 메시지가 있으면 다음 배치로 처리 예약
        if !pendingWatchMessages.isEmpty || !pendingDotMessages.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.processWatchAndDotMessages()
            }
        }
    }
    
    // 기존 코드 유지
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        print("WebSocket 연결 끊김: \(closeCode)")
    }
    
    // 기존 코드 유지
    private func receiveMessages() {
        guard isConnected else { return }
        webSocketTask?.receive { [weak self] result in
            guard let self = self, self.isConnected else { return }
            switch result {
            case .failure(let error):
                print("WebSocket 수신 오류: \(error.localizedDescription)")
            case .success(let message):
                switch message {
                case .string(let text):
                    print("수신한 메시지: \(text)")
                case .data(let data):
                    print("수신한 데이터: \(data)")
                @unknown default:
                    break
                }
            }
            if self.isConnected {
                self.receiveMessages()
            }
        }
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
