import Foundation

// 워치 데이터 전용 웹소켓 매니저
class WatchWebSocketManager: NSObject, URLSessionWebSocketDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    private(set) var isConnected = false
    
    // 워치 전용 웹소켓 URL - 포트를 다르게 설정하여 분리
    //private let serverURL = URL(string: "ws://192.168.45.34:5678/watch")! //집
    private let serverURL = URL(string: "ws://192.168.0.213:5678/watch")!
    
    // 메시지 큐
    private var pendingMessages: [String] = []
    private let maxBufferSize = 100
    private let sendQueue = DispatchQueue(label: "com.sensor.watchSendQueue", qos: .userInteractive)
    
    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
    }
    
    func connect() {
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        receiveMessages()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        print("워치 WebSocket 연결 종료")
    }
    
    func sendMessage(_ message: String) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            print("[WatchWS] send → \(message)")
            if !self.isConnected {
                if self.pendingMessages.count < self.maxBufferSize {
                    self.pendingMessages.append(message)
                }
                return
            }
            
            let wsMessage = URLSessionWebSocketTask.Message.string(message)
            self.webSocketTask?.send(wsMessage) { error in
                if let error = error {
                    print("워치 메시지 전송 오류: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func sendControlMessage(_ message: String) {
        sendMessage(message)
    }
    
    private func receiveMessages() {
        guard isConnected else { return }
        webSocketTask?.receive { [weak self] result in
            guard let self = self, self.isConnected else { return }
            
            switch result {
            case .failure(let error):
                print("워치 WebSocket 수신 오류: \(error.localizedDescription)")
            case .success:
                // 서버로부터 메시지를 받는 경우 처리
                break
            }
            
            self.receiveMessages()
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
        print("워치 WebSocket 연결 성공")
        
        // 보류 중인 메시지 전송
        for message in pendingMessages {
            sendMessage(message)
        }
        pendingMessages.removeAll()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        print("워치 WebSocket 연결 끊김: \(closeCode)")
    }
}

// DOT 데이터 전용 웹소켓 매니저
class DOTWebSocketManager: NSObject, URLSessionWebSocketDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    private(set) var isConnected = false
    
    // DOT 전용 웹소켓 URL - 포트를 다르게 설정하여 분리
    //private let serverURL = URL(string: "ws://192.168.45.34:5678/dot")! //집
    private let serverURL = URL(string: "ws://192.168.0.213:5678/dot")!
    
    // 메시지 큐S$
    private var pendingMessages: [String] = []
    private let maxBufferSize = 100
    private let sendQueue = DispatchQueue(label: "com.sensor.dotSendQueue", qos: .userInteractive)
    
    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
    }
    
    func connect() {
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        receiveMessages()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        print("DOT WebSocket 연결 종료")
    }
    
    func sendMessage(_ message: String) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            print("[DOTWS] send → \(message)")
            
            if !self.isConnected {
                if self.pendingMessages.count < self.maxBufferSize {
                    self.pendingMessages.append(message)
                }
                return
            }
            
            let wsMessage = URLSessionWebSocketTask.Message.string(message)
            self.webSocketTask?.send(wsMessage) { error in
                if let error = error {
                    print("DOT 메시지 전송 오류: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func sendControlMessage(_ message: String) {
        sendMessage(message)
    }
    
    private func receiveMessages() {
        guard isConnected else { return }
        webSocketTask?.receive { [weak self] result in
            guard let self = self, self.isConnected else { return }
            
            switch result {
            case .failure(let error):
                print("DOT WebSocket 수신 오류: \(error.localizedDescription)")
            case .success:
                // 서버로부터 메시지를 받는 경우 처리
                break
            }
            
            self.receiveMessages()
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
        print("DOT WebSocket 연결 성공")
        
        // 보류 중인 메시지 전송
        for message in pendingMessages {
            sendMessage(message)
        }
        pendingMessages.removeAll()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        print("DOT WebSocket 연결 끊김: \(closeCode)")
    }
}
