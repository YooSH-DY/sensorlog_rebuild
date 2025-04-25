import Foundation

class CentralWebSocketManager: NSObject, URLSessionWebSocketDelegate, ObservableObject {
    static let shared = CentralWebSocketManager()
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    @Published var isConnected = false
    private let url = URL(string: "ws://192.168.0.213:5678")!
    private var pending: [String] = []
    private let sendQueue = DispatchQueue(label: "com.sensor.centralWS", qos: .userInitiated)
    
    override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    }
    
    func connect() {
        guard webSocketTask == nil else { return }
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
    }
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
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
    
    // MARK: delegate
    func urlSession(_ s: URLSession, webSocketTask w: URLSessionWebSocketTask,
                    didOpenWithProtocol proto: String?) {
        isConnected = true
        // 보류된 메시지 전송
        pending.forEach { send($0) }
        pending.removeAll()
    }
    func urlSession(_ s: URLSession, webSocketTask w: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
    }
}

// Add notification name for WebSocket send events
extension Notification.Name {
    static let websocketDidSendMessage = Notification.Name("websocketDidSendMessage")
}
