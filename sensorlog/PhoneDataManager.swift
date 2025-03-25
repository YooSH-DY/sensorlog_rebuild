import Foundation
import WatchConnectivity

class PhoneDataManager: NSObject, ObservableObject {
    static let shared = PhoneDataManager()
    
    // 모든 화면에서 사용할 녹화 모드 (RecordMode 또는 Realtime)
    @Published var recordingMode: RecordMode = .record
    
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
    
    private var currentSessionData: [SensorData] = []
    private var expectedChunks = 0
    private var receivedChunks = 0
    private var currentSession: SessionData?   // 워치·DOT가 같이 쌓일 세션
    private var session = WCSession.default
    
    // 실시간으로 받아오는 애플워치 CSV 데이터의 최신값 (헤더: Timestamp,Watch_Acc_X,Watch_Acc_Y,Watch_Acc_Z,Watch_Gyro_X,Watch_Gyro_Y,Watch_Gyro_Z)
    @Published var latestWatchCSV: String?
    private var watchSampleCounter: Int = 0 // 신규: 워치 데이터 샘플 카운터
     
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
    // DOT 센서 녹화 세션 (별도 관리)
    @Published var dotSessions: [DOTSessionData] = []
    
    func sensorDataReceived(_ data: SensorData) {
        guard let session = currentSession else {
            print("세션이 아직 시작되지 않아 워치 데이터 무시")
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        
        // 워치에서 전달받은 CoreMotion 타임스탬프 사용
        let watchTimestamp = formatter.string(from: data.startTimestamp)
        
        let acc = data.accelerometer
        let gyro = data.gyroscope
        
        // 수정: 불필요한 빈 열 제거하고 워치 데이터만 7열로 구성
        let csvRow = "\(watchTimestamp),\(acc.x),\(acc.y),\(acc.z),\(gyro.x),\(gyro.y),\(gyro.z)\n"
        
        print("워치 타임스탬프: " + watchTimestamp)
        // WATCH: 접두사 추가하여 전송
        RealTimeRecordingManager.shared.sendMessage("WATCH:" + csvRow)
        
        DispatchQueue.main.async {
            session.watchSensorData.append(data)
            self.latestWatchCSV = csvRow
        }
    }
    
    func addDOTSession(_ dotSession: DOTSessionData) {
        let sessionData = SessionData(
            id: dotSession.id,
            name: dotSession.name,
            startTimestamp: dotSession.startTimestamp,
            stopTimestamp: dotSession.stopTimestamp,
            watchSensorData: [],
            dotSensorData: dotSession.sensorData.map { dotData in
                return SensorData(
                    id: dotData.id,
                    source: "DOT",
                    startTimestamp: dotData.timestamp,
                    accelerometer: AccelerometerData(
                        x: dotData.accX,
                        y: dotData.accY,
                        z: dotData.accZ,
                        timestamp: dotData.timestamp
                    ),
                    gyroscope: GyroscopeData(
                        x: dotData.gyroX,
                        y: dotData.gyroY,
                        z: dotData.gyroZ,
                        timestamp: dotData.timestamp
                    ),
                    eulerAngles: EulerAngles(
                        roll: dotData.roll,
                        pitch: dotData.pitch,
                        yaw: dotData.yaw
                    ),
                    quaternion:  Quaternion(
                        w: dotData.quatW,
                        x: dotData.quatX,
                        y: dotData.quatY,
                        z: dotData.quatZ
                    )
                )
            }
        )
        
        dotSessions.append(dotSession)
        
        DispatchQueue.main.async {
            self.sessionRecordings.append(sessionData)
            print("DOT 세션 추가됨: \(sessionData.id)")
        }
    }
    
    func deleteDOTSessions(at offsets: IndexSet) {
        dotSessions.remove(atOffsets: offsets)
    }
    func startNewSession() {
        let newName = "session \(sessionRecordings.count + 1)"
        currentSession = SessionData(
            id: UUID(),
            name: newName,
            startTimestamp: Date(),
            watchSensorData: [],
            dotSensorData: []
        )
        // 새로운 세션 시작 시 카운터 초기화
               watchSampleCounter = 0
        print("새 세션 시작: \(currentSession?.id ?? UUID()), 이름: \(newName)")
    }
    
    func stopCurrentSession() {
        guard let session = currentSession else { return }
        session.stopTimestamp = Date()
        DispatchQueue.main.async {
            self.sessionRecordings.append(session)
            print("세션 종료 및 저장: \(session.id)")
            self.currentSession = nil
        }
    }
    
    // 워치에서 날아온 센서 데이터를 추가
    func addSensorData(_ data: SensorData) {
        guard let session = currentSession else { return }
        DispatchQueue.main.async {
            session.watchSensorData.append(data)
        }
    }
    
    func saveRecording(_ data: [SensorData]) {
        DispatchQueue.main.async {
            let newSession = SessionData(
                id: UUID(),
                startTimestamp: data.first?.startTimestamp ?? Date(),
                stopTimestamp: data.last?.stopTimestamp,
                watchSensorData: data,  // 워치 데이터는 이 배열에 저장
                dotSensorData: []       // DOT 데이터는 빈 배열로 초기화
            )
            
            self.sessionRecordings.append(newSession)
            print("새로운 세션이 추가됨: \(newSession.id), 데이터 수: \(data.count)")
            print("전체 세션 수: \(self.sessionRecordings.count)")
        }
    }
    func deleteRecordings(at offsets: IndexSet) {
        DispatchQueue.main.async {
            self.sessionRecordings.remove(atOffsets: offsets)
            print("세션 삭제됨. 남은 세션 수: \(self.sessionRecordings.count)")
        }
    }
    
    //// filepath: /Users/yoosehyeok/Documents/sensorlog_rebuild/sensorlog/PhoneDataManager.swift
    private func completeSession() {
        let sessionNumber = sessionRecordings.count + 1
        let newSession = SessionData(
            id: UUID(),
            name: "세션 \(sessionNumber)",
            startTimestamp: currentSessionData.first?.startTimestamp ?? Date(),
            stopTimestamp: currentSessionData.last?.stopTimestamp,
            watchSensorData: currentSessionData, // 기존의 센서 데이터를 워치 데이터로 저장
            dotSensorData: []                    // DOT 데이터는 빈 배열로 초기화
        )
        
        DispatchQueue.main.async {
            self.sessionRecordings.append(newSession)
            print("새로운 세션이 추가됨: \(newSession.name), 총 데이터 수: \(self.currentSessionData.count)")
        }
        
        // 임시 데이터 초기화
        currentSessionData = []
        expectedChunks = 0
        receivedChunks = 0
    }
    
    func addSession(_ session: SessionData) {
        DispatchQueue.main.async {
            self.sessionRecordings.append(session)
            print("DOT 세션 추가됨: \(session.id)")
        }
    }
    
    func updateSession(_ session: SessionData) {
        if let index = sessionRecordings.firstIndex(where: { $0.id == session.id }) {
            sessionRecordings[index] = session
        }
    }
    // 기존 mergeDOTSession 수정 예시
    // DOT 데이터를 하나의 세션에 합치는 함수
    func mergeDOTSession(with dotSession: DOTSessionData) {
        let newDotData: [SensorData] = dotSession.sensorData.map { dotData in
            return SensorData(
                id: dotData.id,
                source: "DOT",
                startTimestamp: dotData.timestamp,
                accelerometer: AccelerometerData(
                    x: dotData.accX,
                    y: dotData.accY,
                    z: dotData.accZ,
                    timestamp: dotData.timestamp
                ),
                gyroscope: GyroscopeData(
                    x: dotData.gyroX,
                    y: dotData.gyroY,
                    z: dotData.gyroZ,
                    timestamp: dotData.timestamp
                ),
                eulerAngles: EulerAngles(
                    roll: dotData.roll,
                    pitch: dotData.pitch,
                    yaw: dotData.yaw
                ),
                quaternion:  Quaternion(
                    w: dotData.quatW,
                    x: dotData.quatX,
                    y: dotData.quatY,
                    z: dotData.quatZ
                )
            )
        }
        
        // unified 세션(currentSession)이 살아 있는 경우 DOT 데이터를 추가합니다.
        if let session = currentSession {
            session.dotSensorData.append(contentsOf: newDotData)
            if let last = newDotData.last {
                session.stopTimestamp = max(session.stopTimestamp ?? session.startTimestamp, last.startTimestamp)
            }
            print("현재 unified session(\(session.id))에 DOT 데이터 병합 완료: \(newDotData.count)개")
        } else if let lastSession = sessionRecordings.last {
            // 만약 currentSession이 nil이라면 이미 저장된 마지막 세션에 DOT 데이터를 추가합니다.
            lastSession.dotSensorData.append(contentsOf: newDotData)
            if let last = newDotData.last {
                lastSession.stopTimestamp = max(lastSession.stopTimestamp ?? lastSession.startTimestamp, last.startTimestamp)
            }
            print("최근 세션(\(lastSession.id))에 DOT 데이터 병합 완료: \(newDotData.count)개")
        } else {
            // 세션이 전혀 없는 경우, DOT 데이터만으로 새 세션 생성
            let newSession = SessionData(
                startTimestamp: dotSession.startTimestamp,
                stopTimestamp: dotSession.stopTimestamp,
                watchSensorData: [],
                dotSensorData: newDotData
            )
            DispatchQueue.main.async {
                self.sessionRecordings.append(newSession)
            }
            print("새 DOT 세션 생성: \(newSession.id)")
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
    
    func sessionDidBecomeInactive(_ session: WCSession) { }
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // 워치 센서 데이터 타입 처리
        if let type = message["type"] as? String, type == "watchSensorData",
           let timestamp = message["timestamp"] as? TimeInterval,
           let accX = message["accX"] as? Double,
           let accY = message["accY"] as? Double,
           let accZ = message["accZ"] as? Double,
           let gyroX = message["gyroX"] as? Double,
           let gyroY = message["gyroY"] as? Double,
           let gyroZ = message["gyroZ"] as? Double {
            
            let sensorData = SensorData(
                id: UUID(),
                startTimestamp: Date(timeIntervalSince1970: timestamp),
                stopTimestamp: nil,
                accelerometer: AccelerometerData(x: accX, y: accY, z: accZ, timestamp: Date(timeIntervalSince1970: timestamp)),
                gyroscope: GyroscopeData(x: gyroX, y: gyroY, z: gyroZ, timestamp: Date(timeIntervalSince1970: timestamp)),
                eulerAngles: nil,
                quaternion: nil
            )
            DispatchQueue.main.async {
                self.sensorDataReceived(sensorData)
            }
        }
        // 기존 DOT 센서 데이터 청크 처리 코드 (있는 경우)
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

extension PhoneDataManager {
    func sendWatchCommand(_ command: String) {
        let message: [String: Any] = ["command": command]
        session.sendMessage(message, replyHandler: nil) { error in
            print("워치로 명령 전송 실패: \(error.localizedDescription)")
        }
    }
}

