import Foundation

class RealTimeRecordingManager: NSObject, URLSessionWebSocketDelegate, ObservableObject {
    static let shared = RealTimeRecordingManager()
    
    private var webSocketTask: URLSessionWebSocketTask?
    private(set) var isConnected = false
    //private let serverURL = URL(string: "ws://192.168.45.34:5678")! //집
    private let serverURL = URL(string: "ws://192.168.0.213:5678")!  // 실제 접속 가능한 서버 IP
    private var session: URLSession!
    
    // 센서 데이터 큐: 연결 전에는 임시 저장 후 연결되면 전송
    private var pendingMessages: [String] = []
    
    override init() {
        super.init()
        // delegateQueue를 메인 큐로 지정하여 delegate 콜백이 메인 스레드에서 호출되도록 함
        let configuration = URLSessionConfiguration.default
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
    }
    
    func connect() {
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        // 연결이 열릴 때까지 잠시 대기하는 로직은 delegate에서 처리됨
        // 바로 센서 데이터를 보내지 않고 pendingMessages에 저장
    }
    
    func disconnect(completion: (() -> Void)? = nil) {
        sendMessage("SESSION_END")  // 세션 종료 메시지 전송
        pendingMessages.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self.isConnected = false
            print("WebSocket 연결이 지연 후 종료됨")
            completion?()
        }
    }
    
    // delegate에서 연결이 열릴 때 isConnected를 true로 설정한 후, pendingMessages에 저장된 메시지를 전송
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        isConnected = true
        print("WebSocket connection opened")
        // SESSION_START 메시지를 보냄
        sendMessage("SESSION_START")
        // 연결 전에 보류했던 메시지 전송
        for message in pendingMessages {
            sendMessage(message)
        }
        pendingMessages.removeAll()
        
        // 이후 계속 수신
        receiveMessages()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        print("WebSocket connection closed: \(closeCode)")
    }
    
    func sendMessage(_ message: String) {
        // 만약 연결이 안되어 있다면 pendingMessages에 저장
        guard isConnected, let task = webSocketTask else {
            print("WebSocket 연결이 열리지 않았거나 이미 닫혔습니다. 메시지 보류: \(message)")
            pendingMessages.append(message)
            return
        }
        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        task.send(wsMessage) { error in
            if let error = error {
                print("WebSocket 전송 오류: \(error.localizedDescription)")
            } else {
                //print("전송한 메시지: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
    }
    
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
    
    // 센서 데이터를 CSV 형식 문자열로 전송
    func sendSensorData(_ data: SensorData) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: data.startTimestamp)
        let csvLine = "\(timestamp),\(data.accelerometer.x),\(data.accelerometer.y),\(data.accelerometer.z),\(data.gyroscope.x),\(data.gyroscope.y),\(data.gyroscope.z)"
        sendMessage(csvLine)
    }
}
