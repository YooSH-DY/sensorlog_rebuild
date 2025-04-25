import Foundation

class CentralWebSocketManager: NSObject, URLSessionWebSocketDelegate, ObservableObject {
    static let shared = CentralWebSocketManager()
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    @Published var isConnected = false
    private let url = URL(string: "ws://192.168.0.213:5678")!
    private var pending: [String] = []
    private let sendQueue = DispatchQueue(label: "com.sensor.centralWS", qos: .userInitiated)
    // 연결 완료 콜백 추가
    private var connectionCompletion: ((Bool) -> Void)?
    private var pingTimer: Timer?

    override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    }
    
    func connect(completion: ((Bool) -> Void)? = nil) {
        // 이미 연결되어 있으면 바로 콜백 실행
        if isConnected {
            completion?(true)
            return
        }
        
        // 콜백 저장
        self.connectionCompletion = completion
        // 핑 타이머 시작
            startPingTimer()
        // 기존 연결 코드
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        // 메시지 수신 시작
            receiveMessages()
        // 타임아웃 설정 (5초 내에 연결 안되면 실패로 간주)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            if self?.isConnected == false {
                self?.connectionCompletion?(false)
                self?.connectionCompletion = nil
            }
        }
    }
    func disconnect() {
        print("웹소켓 연결 종료 요청")
        
        // 핑 타이머 즉시 중지 (메인 스레드에서 실행)
        DispatchQueue.main.async {
            self.pingTimer?.invalidate()
            self.pingTimer = nil
            print("핑 타이머 중지됨")
        }
        
        // 웹소켓 연결 종료 메시지 전송 (종료 의도 전달)
        let closeMessage = "{\"type\":\"close\",\"timestamp\":\(Date().timeIntervalSince1970)}"
        send(closeMessage)
        
        // 웹소켓 태스크 취소
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        
        print("웹소켓 연결 종료 완료")
    }
    func send(_ text: String) {
        sendQueue.async { [weak self] in
            // 로그 출력: 전송할 메시지 콘솔에 표시
            print("[WS Send] \(text)")
            NotificationCenter.default.post(name: .websocketDidSendMessage, object: text)
            guard let self = self else { return }
            if !self.isConnected {
                self.pending.append(text)
                self.connect()
                return
            }
            let msg = URLSessionWebSocketTask.Message.string(text)
            self.webSocketTask?.send(msg) { error in /* ignore or log */ }
        }
    }
    
    // 핑 타이머 시작 메서드 추가
    private func startPingTimer() {
        pingTimer?.invalidate()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.pingTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
                guard let self = self,
                      self.isConnected,
                      self.webSocketTask != nil else {  // 추가 검사
                    // 조건 불충족 시 타이머 중지
                    DispatchQueue.main.async {
                        self?.pingTimer?.invalidate()
                        self?.pingTimer = nil
                        print("핑 타이머 자동 중지됨: 연결 종료 감지")
                    }
                    return
                }
                
                // 서버가 이해할 수 있는 ping 메시지 전송
                let pingMessage = "{\"type\":\"ping\",\"timestamp\":\(Date().timeIntervalSince1970)}"
                self.send(pingMessage)
            }
            
            RunLoop.main.add(self.pingTimer!, forMode: .common)
        }
    }
    // didOpenWithProtocol 메서드 수정
    func urlSession(_ s: URLSession, webSocketTask w: URLSessionWebSocketTask,
                   didOpenWithProtocol proto: String?) {
        isConnected = true
        
        // 보류된 메시지 전송
        pending.forEach { send($0) }
        pending.removeAll()
        
        // 연결 완료 콜백 실행
        connectionCompletion?(true)
        connectionCompletion = nil
        // 즉시 ping 보내서 연결 확인
            let pingMessage = "{\"type\":\"ping\",\"timestamp\":\(Date().timeIntervalSince1970)}"
            self.send(pingMessage)
            
            // 메시지 수신 시작
            receiveMessages()
    }
    // urlSession:webSocketTask:didCloseWith: 메서드 수정
    func urlSession(_ s: URLSession, webSocketTask w: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        print("웹소켓 연결 끊김 감지: \(closeCode)")
        
        // 약간의 지연 후 자동 재연결 시도
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            print("웹소켓 자동 재연결 시도")
            self?.connect()
        }
    }
    // CentralWebSocketManager.swift에 추가
    private func receiveMessages() {
        guard let task = webSocketTask, isConnected else { return }
        
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    // 퐁 메시지 처리
                    if text.contains("\"type\":\"pong\"") {
                        print("퐁 메시지 수신: \(Date().timeIntervalSince1970)")
                    }
                case .data:
                    break
                @unknown default:
                    break
                }
                
                // 계속해서 다음 메시지 수신
                self.receiveMessages()
                
            case .failure(let error):
                print("메시지 수신 오류: \(error.localizedDescription)")
                if self.isConnected {
                    self.isConnected = false
                    // 재연결 시도
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.connect()
                    }
                }
            }
        }
    }
}

// Add notification name for WebSocket send events
extension Notification.Name {
    static let websocketDidSendMessage = Notification.Name("websocketDidSendMessage")
}
