import Foundation
import WatchConnectivity

class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()
    
    // 워치 데이터만 저장하는 세션
    @Published var currentSession: SessionData?
    @Published var sessionRecordings: [SessionData] = []
    @Published var isRecording = false
    
    // 실시간으로 받아오는 워치 CSV 데이터 최신값
    @Published var latestWatchCSV: String?
    
    // 웹소켓 전용 매니저
    private var session = WCSession.default
    
    override init() {
        super.init()
        setupWCSession()
    }
    
    private func setupWCSession() {
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }
    
    // WatchSessionManager.swift 내에 세션 변경 알림 추가

    func startNewSession() {
        let newName = "Watch Session \(sessionRecordings.count + 1)"
        currentSession = SessionData(
            id: UUID(),
            name: newName,
            startTimestamp: Date(),
            watchSensorData: [],
            dotSensorData: []
        )
        isRecording = true
        print("워치 세션 시작: \(newName), 세션 ID: \(currentSession?.id.uuidString ?? "nil")")
        CentralWebSocketManager.shared.connect()
        CentralWebSocketManager.shared.send("WATCH_SESSION_START")
    }


    func stopCurrentSession() {
        guard let session = currentSession else { return }
        session.stopTimestamp = Date()
        
        CentralWebSocketManager.shared.send("WATCH_SESSION_END")
        CentralWebSocketManager.shared.disconnect()
        
        DispatchQueue.main.async {
            self.sessionRecordings.append(session)
            print("워치 세션 종료 및 저장: \(session.id)")
            self.currentSession = nil
            self.isRecording = false
            
            // 세션 변경 알림
            NotificationCenter.default.post(name: NSNotification.Name("SessionUpdated"), object: nil)
        }
    }
    
    // 워치 명령 전송
    func sendWatchCommand(_ command: String) {
        let message = ["command": command]
        session.sendMessage(message, replyHandler: nil) { error in
            print("워치 명령 전송 실패: \(error.localizedDescription)")
        }
    }
    
    // 워치 데이터 수신 처리
    func sensorDataReceived(_ data: SensorData) {
        // currentSession이 nil인 경우 자동으로 새 세션 생성
        if currentSession == nil {
            print("워치 데이터 수신됨: 세션이 없어 자동으로 새 세션 생성")
            let newName = "Watch Session \(sessionRecordings.count + 1) (Auto)"
            currentSession = SessionData(
                id: UUID(),
                name: newName,
                startTimestamp: Date(),
                watchSensorData: [],
                dotSensorData: []
            )
            CentralWebSocketManager.shared.connect()
            CentralWebSocketManager.shared.send("WATCH_SESSION_START")
            isRecording = true
        }
        
        guard let session = currentSession else {
            print("세션이 아직 시작되지 않아 워치 데이터 무시")
            return
        }
        
        // 1. 모든 데이터는 세션에 저장 (세션 상세정보에서 볼 수 있도록)
        DispatchQueue.main.async {
            session.watchSensorData.append(data)
            //print("워치 데이터 세션에 저장됨: 현재 개수 \(session.watchSensorData.count)")
        }
        
        // 2. 웹소켓으로는 Yaw 데이터만 전송 (실시간 연동용)
        if let eulerAngles = data.eulerAngles {
            let yaw = eulerAngles.yaw
            let roll = eulerAngles.roll
            let pitch = eulerAngles.pitch
            // 최적화된 웹소켓 전송 문자열 생성 및 타입 태그 포함 JSON 전송
            let shortTimestamp = String(format: "%.3f", data.startTimestamp.timeIntervalSince1970)
            let messageDict: [String: Any] = [
                "type": "watch",
                "timestamp": data.startTimestamp.timeIntervalSince1970,
                "r": String(format: "%.2f", roll),
                "p": String(format: "%.2f", pitch),
                "y": String(format: "%.2f", yaw)
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: messageDict),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                CentralWebSocketManager.shared.send(jsonString)
            }
        } else if let quaternion = data.quaternion {
            // 쿼터니언에서 Yaw 계산 (eulerAngles가 nil인 경우)
            let eulerAngles = calculateEulerFromQuaternion(quaternion)
            let yaw = eulerAngles.yaw
            let roll = eulerAngles.roll
            let pitch = eulerAngles.pitch
            
            // 최적화된 웹소켓 전송 문자열 생성 및 타입 태그 포함 JSON 전송
            let shortTimestamp = String(format: "%.3f", data.startTimestamp.timeIntervalSince1970)
            let messageDict: [String: Any] = [
                "type": "watchSensorData",
                "timestamp": data.startTimestamp.timeIntervalSince1970,
                "r": String(format: "%.2f", roll),
                "p": String(format: "%.2f", pitch),
                "y": String(format: "%.2f", yaw)
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: messageDict),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                CentralWebSocketManager.shared.send(jsonString)
            }
        }
    }
    // 쿼터니언에서 오일러 각도 계산 함수 추가
    private func calculateEulerFromQuaternion(_ quaternion: Quaternion) -> EulerAngles {
        let w = quaternion.w
        let x = quaternion.x
        let y = quaternion.y
        let z = quaternion.z
        
        // 롤 (x-축 회전)
        let roll = atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y))
        
        // 피치 (y-축 회전)
        let sinp = 2.0 * (w * y - z * x)
        let pitch = abs(sinp) >= 1 ? (sinp > 0 ? .pi/2 : -.pi/2) : asin(sinp)
        
        // 요 (z-축 회전)
        let yaw = atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))
        
        // 라디안에서 각도로 변환
        return EulerAngles(
            roll: roll * (180.0 / .pi),
            pitch: pitch * (180.0 / .pi),
            yaw: yaw * (180.0 / .pi)
        )
    }
}

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession 활성화 실패:", error.localizedDescription)
        } else {
            print("WCSession 활성화 완료: \(activationState.rawValue)")
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) { }
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    
//    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
//        // 워치 센서 데이터 타입 처리 - Yaw만 수신
//        if let type = message["type"] as? String, type == "watchSensorData",
//           let timestamp = message["timestamp"] as? TimeInterval,
//           let yaw = message["yaw"] as? Double {
//            
//            let date = Date(timeIntervalSince1970: timestamp)
//            
//            // 워치에서는 Yaw만 제공하지만, 누락된 값들도 모두 포함하는 완전한 구조체 생성
//            let sensorData = SensorData(
//                id: UUID(),
//                source: "WATCH",
//                startTimestamp: date,
//                stopTimestamp: nil,
//                accelerometer: AccelerometerData(x: 0, y: 0, z: 0, timestamp: date),
//                gyroscope: GyroscopeData(x: 0, y: 0, z: 0, timestamp: date),
//                eulerAngles: EulerAngles(roll: 0, pitch: 0, yaw: yaw),
//                quaternion: Quaternion(w: 1.0, x: 0.0, y: 0.0, z: 0.0) // 가상의 쿼터니언 값 추가
//            )
//            
//            DispatchQueue.main.async {
//                self.sensorDataReceived(sensorData)
//            }
//        }
//        // 청크 처리 코드는 기존과 동일하게 유지
//    }
}
