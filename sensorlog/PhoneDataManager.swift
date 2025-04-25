import Foundation
import WatchConnectivity

class PhoneDataManager: NSObject, ObservableObject {
    static let shared = PhoneDataManager()
    
    // 모든 화면에서 사용할 녹화 모드 (RecordMode 또는 Realtime)
    @Published var recordingMode: RecordMode = .realtime
    
    @Published var sessionRecordings: [SessionData] = [] {
        didSet {
            // 세션 변경 사항을 감지하기 위한 구독 설정
            for session in sessionRecordings {
                if session.objectWillChange.sink(receiveValue: { [weak self] _ in
                    self?.objectWillChange.send()
                }).cancel() == nil {} // 메모리 누수 방지
            }
        }
    }
    private var pendingWatchCommands: [String] = []
    // 별도 세션 매니저 참조
    private let watchSessionManager = WatchSessionManager.shared
    private let dotSessionManager = DOTSessionManager.shared
    
    private var currentSessionData: [SensorData] = []
    private var expectedChunks = 0
    private var receivedChunks = 0
    private var currentSession: SessionData?   // 워치·DOT가 같이 쌓일 세션 (레코드 모드용)
    private var session = WCSession.default
    
    // 실시간으로 받아오는 애플워치 CSV 데이터의 최신값
    @Published var latestWatchCSV: String?
    private var watchSampleCounter: Int = 0
     
    override init() {
        super.init()
        setupWCSession()
        setupObservers()
    }
    
    private func setupWCSession() {
      let session = WCSession.default
      session.delegate = self
      session.activate()
      print("폰: WCSession 활성화")
    }
    
    // 세션 매니저 변화 감지 설정
    private func setupObservers() {
        // 각 매니저의 세션 변경 시 통합 세션 목록 업데이트
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionUpdated),
            name: NSNotification.Name("SessionUpdated"),
            object: nil)
    }
    
    @objc private func sessionUpdated() {
        mergeAllSessions()
    }
    
    // DOT 센서 녹화 세션 (별도 관리)
    @Published var dotSessions: [DOTSessionData] = []
    
    // 리얼타임 모드와 레코드 모드를 구분해서 처리하는 녹화 시작 함수
    func startRecording() {
        if recordingMode == .realtime {
            // 리얼타임 모드: 별도 세션 관리자를 통해 처리
            startRealtimeRecording()
        } else {
            // 레코드 모드: 기존 방식대로 통합 세션 처리
            startRecordModeRecording()
        }
    }
    
    // 리얼타임 모드 녹화 시작 (별도 세션 방식)
    private func startRealtimeRecording() {
        // 워치에 리얼타임 모드 시작 명령 전송
        sendWatchCommand("start_realtime")
        
        // 워치 세션 시작 (추가)
        watchSessionManager.startNewSession()
        
        // DOT 세션은 ContentView에서 직접 DOTSessionManager를 통해 시작됨
        // (DOT 디바이스 필요)
        
        // 통합 세션 목록 업데이트
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.mergeAllSessions()
        }
    }
    
    // 레코드 모드 녹화 시작 (기존 통합 세션 방식)
    private func startRecordModeRecording() {
        // 워치에 레코드 모드 시작 명령 전송
        sendWatchCommand("start")
        
        // 통합 세션 생성
        let newName = "session \(sessionRecordings.count + 1)"
        currentSession = SessionData(
            id: UUID(),
            name: newName,
            startTimestamp: Date(),
            watchSensorData: [],
            dotSensorData: []
        )
        
        watchSampleCounter = 0
        print("새 세션 시작 (레코드 모드): \(currentSession?.id ?? UUID()), 이름: \(newName)")
    }
    
    // 녹화 중지
    func stopRecording() {
        if recordingMode == .realtime {
            // 리얼타임 모드: 별도 세션 중지
            stopRealtimeRecording()
        } else {
            // 레코드 모드: 통합 세션 중지
            stopRecordModeRecording()
        }
    }
    
    // 리얼타임 모드 녹화 중지
    private func stopRealtimeRecording() {
        // 워치에 리얼타임 중지 명령 전송
        sendWatchCommand("stop_realtime")
        
        // 워치 세션 중지 (추가)
        watchSessionManager.stopCurrentSession()
        
        // DOT 세션은 ContentView에서 직접 DOTSessionManager를 통해 중지됨
        
        // 통합 세션 목록 업데이트
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.mergeAllSessions()
        }
    }
    
    // 레코드 모드 녹화 중지
    private func stopRecordModeRecording() {
        // 워치에 녹화 중지 명령 전송
        sendWatchCommand("stop")
        
        // 통합 세션 종료 및 저장
        guard let session = currentSession else { return }
        session.stopTimestamp = Date()
        
        DispatchQueue.main.async {
            self.sessionRecordings.append(session)
            print("세션 종료 및 저장 (레코드 모드): \(session.id)")
            self.currentSession = nil
        }
    }
    
    // 모든 세션을 병합하여 View용 목록 생성
    func mergeAllSessions() {
        DispatchQueue.main.async {
            var allSessions: [SessionData] = []
            
            // 통합 세션(레코드 모드)
            if let current = self.currentSession {
                allSessions.append(current)
            }
            
            // 기존 기록된 세션
            allSessions.append(contentsOf: self.sessionRecordings)
            
            // 워치 전용 세션
            allSessions.append(contentsOf: self.watchSessionManager.sessionRecordings)
            
            // DOT 전용 세션
            allSessions.append(contentsOf: self.dotSessionManager.sessionRecordings)
            
            // 중복 제거 (ID 기준)
            var uniqueSessions: [SessionData] = []
            var seenIDs: Set<UUID> = []
            
            for session in allSessions {
                if !seenIDs.contains(session.id) {
                    uniqueSessions.append(session)
                    seenIDs.insert(session.id)
                }
            }
            
            // 날짜 기준 내림차순 정렬
            self.sessionRecordings = uniqueSessions.sorted {
                $0.startTimestamp > $1.startTimestamp
            }
        }
    }
    
    // 이하 기존 코드들...
    
    func sensorDataReceived(_ data: SensorData) {
        if recordingMode == .realtime {
            // 리얼타임 모드: 워치 세션 매니저로 전달
            watchSessionManager.sensorDataReceived(data)
        } else {
            // 레코드 모드: 기존 통합 세션에 추가
            guard let session = currentSession else {
                print("세션이 아직 시작되지 않아 워치 데이터 무시")
                return
            }
            
            // 이미 완전한 SensorData 객체가 생성되었으므로 그대로 사용
            DispatchQueue.main.async {
                session.watchSensorData.append(data)
            }
        }
    }
    
    // 세션 삭제
    func deleteRecordings(at offsets: IndexSet) {
        let idsToDelete = offsets.map { sessionRecordings[$0].id }
        
        DispatchQueue.main.async {
            // 통합 세션 목록에서 삭제
            self.sessionRecordings.remove(atOffsets: offsets)
            
            // 워치 세션 매니저에서도 해당 ID 삭제
            for id in idsToDelete {
                if let index = self.watchSessionManager.sessionRecordings.firstIndex(where: { $0.id == id }) {
                    self.watchSessionManager.sessionRecordings.remove(at: index)
                }
            }
            
            // DOT 세션 매니저에서도 해당 ID 삭제
            for id in idsToDelete {
                if let index = self.dotSessionManager.sessionRecordings.firstIndex(where: { $0.id == id }) {
                    self.dotSessionManager.sessionRecordings.remove(at: index)
                }
            }
            
            print("세션 삭제됨. 남은 세션 수: \(self.sessionRecordings.count)")
        }
    }
    
    // 기존 mergeDOTSession 수정 - 레코드 모드 전용
    func mergeDOTSession(with dotSession: DOTSessionData) {
        // 레코드 모드일 때만 기존 세션에 병합
        if recordingMode == .record {
            // 기존 코드 그대로 유지...
            // (Quaternion을 사용하는 코드)
        } else {
            // 리얼타임 모드에서는 DOT 세션 매니저로 위임
            dotSessionManager.addDOTSession(dotSession)
        }
        
        // 통합 세션 목록 업데이트
        mergeAllSessions()
    }
    
    // 기존 sendWatchCommand 유지
    func sendWatchCommand(_ command: String) {
        let message = ["command": command]
        // ① 네트워크가 준비되지 않았으면 재시도 버퍼링
        guard WCSession.default.isReachable else {
            print("📴 워치 Unreachable → 버퍼링: \(command)")
            pendingWatchCommands.append(command)  // pendingWatchCommands: [String]
            return
        }
        // ② 준비된 상태에서 전송
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("워치로 명령 전송 실패: \(error.localizedDescription)")
        }
    }
}
    
extension PhoneDataManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession 활성화 실패:", error.localizedDescription)
        } else {
            print("WCSession 활성화 완료: \(activationState.rawValue)")
        }
    }
    func sessionWatchStateDidChange(_ session: WCSession) {
            if session.isReachable {
                // 버퍼에 남은 명령 모두 전송
                pendingWatchCommands.forEach { sendWatchCommand($0) }
                pendingWatchCommands.removeAll()
            }
        }
    func sessionDidBecomeInactive(_ session: WCSession) { }
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // 전체 워치 데이터 (모든 센서 정보 포함)
        if let type = message["type"] as? String, type == "watchSensorDataFull",
           let timestamp = message["timestamp"] as? TimeInterval,
           let accX = message["accX"] as? Double,
           let accY = message["accY"] as? Double,
           let accZ = message["accZ"] as? Double,
           let gyroX = message["gyroX"] as? Double,
           let gyroY = message["gyroY"] as? Double,
           let gyroZ = message["gyroZ"] as? Double,
           let roll = message["roll"] as? Double,
           let pitch = message["pitch"] as? Double,
           let yaw = message["yaw"] as? Double,
           let quatW = message["quatW"] as? Double,
           let quatX = message["quatX"] as? Double,
           let quatY = message["quatY"] as? Double,
           let quatZ = message["quatZ"] as? Double {
            
            let date = Date(timeIntervalSince1970: timestamp)
            
            // 모든 센서 데이터를 포함한 완전한 SensorData 객체 생성
            let sensorData = SensorData(
                id: UUID(),
                source: "WATCH",
                startTimestamp: date,
                stopTimestamp: nil,
                accelerometer: AccelerometerData(x: accX, y: accY, z: accZ, timestamp: date),
                gyroscope: GyroscopeData(x: gyroX, y: gyroY, z: gyroZ, timestamp: date),
                eulerAngles: EulerAngles(roll: roll, pitch: pitch, yaw: yaw),
                quaternion: Quaternion(w: quatW, x: quatX, y: quatY, z: quatZ)
            )
            
            DispatchQueue.main.async {
                self.sensorDataReceived(sensorData)
                
                // 리얼타임 모드에서는 웹소켓으로도 직접 전송 (추가적인 보험)
//                if self.recordingMode == .realtime {
//                    let shortTimestamp = String(format: "%.3f", date.timeIntervalSince1970)
//                    let optimizedRow = "t:\(shortTimestamp),y:\(yaw)"
//                    RealTimeRecordingManager.shared.sendWatchMessage("W:" + optimizedRow)
//                    print("PhoneDataManager에서 직접 웹소켓 전송: \(optimizedRow)")
//                }
            }
        }
        // 간소화된 실시간 워치 데이터 (Yaw만 포함)
        else if let type = message["type"] as? String, type == "watchSensorData",
                    let timestamp = message["timestamp"] as? TimeInterval,
                    let yaw = message["yaw"] as? Double {
                
                let date = Date(timeIntervalSince1970: timestamp)
                
                // 메인 스레드에서만 Published 속성과 모델 갱신
            DispatchQueue.main.async {
                if self.recordingMode == .realtime {
                    // 1) 웹소켓 전송
                    let shortTimestamp = String(format: "%.3f", date.timeIntervalSince1970)
                    let optimizedRow = "t:\(shortTimestamp),y:\(yaw)"
                    //RealTimeRecordingManager.shared.sendWatchMessage("W:" + optimizedRow)
                    
                    // 2) UI/모델 업데이트
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
                    formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
                    let formattedTimestamp = formatter.string(from: date)
                    self.latestWatchCSV = "\(formattedTimestamp),0,0,0,0,0,0,0,0,\(yaw)\n"
                    
                    // 3) 세션에 저장
                    let sensorData = SensorData(
                        id: UUID(),
                        source: "WATCH",
                        startTimestamp: date,
                        stopTimestamp: nil,
                        accelerometer: AccelerometerData(x: 0, y: 0, z: 0, timestamp: date),
                        gyroscope: GyroscopeData(x: 0, y: 0, z: 0, timestamp: date),
                        eulerAngles: EulerAngles(roll: 0, pitch: 0, yaw: yaw),
                        quaternion: Quaternion(w: 1.0, x: 0, y: 0, z: 0)
                    )
                    //self.watchSessionManager.sensorDataReceived(sensorData)
                }
            }
        }
        
        // 청크 처리 코드 (레코드 모드에 사용)
        else if let base64String = message["data"] as? String,
                let chunkIndex = message["chunkIndex"] as? Int,
                let totalChunks = message["totalChunks"] as? Int {
            do {
                if let jsonData = Data(base64Encoded: base64String) {
                    let decodedChunk = try JSONDecoder().decode([SensorData].self, from: jsonData)
                    
                    DispatchQueue.main.async {
                        for data in decodedChunk {
                            self.sensorDataReceived(data)
                        }
                        print("청크 \(chunkIndex + 1)/\(totalChunks) 수신됨 (누적 데이터: \(decodedChunk.count)개 추가)")
                    }
                }
            } catch {
                print("JSON 디코딩 실패:", error.localizedDescription)
            }
        }
    }
}
