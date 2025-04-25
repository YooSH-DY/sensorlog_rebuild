import Foundation
import MovellaDotSdk

class DOTSessionManager: NSObject, ObservableObject {
    static let shared = DOTSessionManager()
    
    // 각 DOT 장치별 실시간 세션 관리
    private var activeSessions: [String: SessionData] = [:]

    // 연결 순서 매핑: uuid -> 1, 2, 3...
    private var deviceOrderMap: [String: Int] = [:] // ★ 추가

    // DOT 데이터만 저장하는 세션
    @Published var currentSession: SessionData?
    @Published var sessionRecordings: [SessionData] = []
    @Published var isRecording = false
    
    // 실시간으로 받아오는 DOT CSV 데이터 최신값
    @Published var latestDOTCSV: String?
    
    override init() {
        super.init()
    }
    
    func startNewSession() {
        let newName = "DOT Session \(sessionRecordings.count + 1)"
        currentSession = SessionData(
            id: UUID(),
            name: newName,
            startTimestamp: Date(),
            watchSensorData: [],  // DOT 세션이므로 항상 빈 배열
            dotSensorData: []
        )
        isRecording = true
        
        // DOT 웹소켓 연결 시작
        CentralWebSocketManager.shared.connect()
        CentralWebSocketManager.shared.send("DOT_SESSION_START")
        
        // 세션 변경 알림
        NotificationCenter.default.post(name: NSNotification.Name("SessionUpdated"), object: nil)
    }

    func stopCurrentSession() {
        guard let session = currentSession else { return }
        session.stopTimestamp = Date()
        
        CentralWebSocketManager.shared.send("DOT_SESSION_END")
        CentralWebSocketManager.shared.disconnect()
        
        DispatchQueue.main.async {
            self.sessionRecordings.append(session)
            print("DOT 세션 종료 및 저장: \(session.id)")
            self.currentSession = nil
            self.isRecording = false
            
            // 세션 변경 알림
            NotificationCenter.default.post(name: NSNotification.Name("SessionUpdated"), object: nil)
        }
    }
    // DOT 세션 추가 메서드
    func addDOTSession(_ dotSession: DOTSessionData) {
        // DOTSessionData를 SessionData로 변환
        let sessionData = SessionData(
            id: dotSession.id,
            name: dotSession.name,
            startTimestamp: dotSession.startTimestamp,
            stopTimestamp: dotSession.stopTimestamp,
            watchSensorData: [],  // DOT 데이터만 포함
            dotSensorData: dotSession.sensorData.map { dotData in
                return SensorData(
                    id: dotData.id,
                    source: "DOT",
                    startTimestamp: dotData.timestamp,
                    stopTimestamp: nil,
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
                    quaternion: Quaternion(
                        w: dotData.quatW,
                        x: dotData.quatX,
                        y: dotData.quatY,
                        z: dotData.quatZ
                    )
                )
            }
        )
        
        // 세션 목록에 추가
        DispatchQueue.main.async {
            self.sessionRecordings.append(sessionData)
            print("DOT 세션 추가됨: \(sessionData.id)")
            
            // 세션 변경 알림
            NotificationCenter.default.post(name: NSNotification.Name("SessionUpdated"), object: nil)
        }
    }
    
    // 외부에서 생성된 세션을 추가
    func addSession(_ session: SessionData) {
        DispatchQueue.main.async {
            self.sessionRecordings.append(session)
            // 날짜순 정렬
            self.sessionRecordings.sort { $0.startTimestamp > $1.startTimestamp }
        }
    }
    // DOT 데이터 수신 처리
    func sensorDataReceived(_ data: SensorData) {
        guard let session = currentSession else {
            print("세션이 아직 시작되지 않아 DOT 데이터 무시")
            return
        }
        
        // 웹소켓으로 Roll 데이터만 전송
        if let eulerAngles = data.eulerAngles {
            let roll = eulerAngles.roll
            
            // 최적화된 웹소켓 전송 문자열
            let shortTimestamp = String(format: "%.3f", data.startTimestamp.timeIntervalSince1970)
            let optimizedRow = "t:\(shortTimestamp),r:\(roll)"
            
            // 웹소켓으로 전송
            CentralWebSocketManager.shared.send(optimizedRow)
        }
        
        // 이 부분의 클로저 구문을 수정
        DispatchQueue.main.async {
            session.dotSensorData.append(data)
        }
    }
    
    // DOT 실시간 녹화 시작
    func startRealTimeRecording(for device: DotDevice) {
        // 이게 웹소켓전송시 hz설정
        device.setOutputRate(20, filterIndex: 0)
        device.plotMeasureMode = .customMode4
        device.plotMeasureEnable = true
        
        let cleanMAC = device.macAddress.replacingOccurrences(of: ":", with: "").uppercased()
        let macSuffix = String(cleanMAC.suffix(2))
        let fullKey = cleanMAC
        let countForDevice = sessionRecordings.filter { $0.name.hasPrefix("DOT(") && $0.name.contains(macSuffix) }.count

        // 연결 순서
        if deviceOrderMap[device.uuid] == nil {
            deviceOrderMap[device.uuid] = deviceOrderMap.count + 1
        }
        let wsPrefix = "DOT\(deviceOrderMap[device.uuid]!)"

        // 새 세션 생성 및 저장
        let session = SessionData(
            id: UUID(),
            name: "DOT(\(macSuffix)) Session \(countForDevice + 1)",
            startTimestamp: Date(),
            watchSensorData: [],
            dotSensorData: []
        )
        activeSessions[fullKey] = session
        let sessionRef = session
        DispatchQueue.main.async {
            self.currentSession = session
            self.isRecording = true
        }

        CentralWebSocketManager.shared.connect()
        CentralWebSocketManager.shared.send("DOT_SESSION_START")
        print("DOT RealTime 녹화 시작: \(macSuffix) - Session \(countForDevice + 1)")

        let sessionStartTime = Date()
        var firstSampleTime: UInt32? = nil
        
        device.setDidParsePlotDataBlock { [weak self] plotData in
            guard let self = self else { return }
            // 기존 deviceIndex/connectedDots 사용 부분 제거
            // let deviceIndex = DotManager.shared.connectedDots.firstIndex { $0.uuid == device.uuid } ?? 0
            // let wsPrefix = "DOT\(deviceIndex + 1)"
            // wsPrefix는 위에서 이미 할당됨

            // 최초 샘플 시간 설정
            if firstSampleTime == nil {
                firstSampleTime = plotData.timeStamp
            }
            let timeOffset = Double(plotData.timeStamp - (firstSampleTime!)) / 1_000_000.0
            let actualTimestamp = sessionStartTime.addingTimeInterval(timeOffset)
            // 센서 데이터 생성
            // 1. 모든 센서 데이터 수집
            // 가속도, 자이로, 쿼터니언 데이터 추출
            let accX = plotData.acc0
            let accY = plotData.acc1
            let accZ = plotData.acc2
            let gyroX = plotData.gyr0
            let gyroY = plotData.gyr1
            let gyroZ = plotData.gyr2
            let quatW = plotData.quatW
            let quatX = plotData.quatX
            let quatY = plotData.quatY
            let quatZ = plotData.quatZ
            
            // 오일러 각 계산 (Quat -> Euler 변환)
            var euler: [Double] = [0.0, 0.0, 0.0]
            DotUtils.quat(toEuler: &euler,
                          withW: plotData.quatW,
                          withX: plotData.quatX,
                          withY: plotData.quatY,
                          withZ: plotData.quatZ)
            
            // 각도값 추출
            let roll = euler[0]
            let pitch = euler[1]
            let yaw = euler[2]
            
            // 모든 센서 데이터를 포함한 완전한 SensorData 객체 생성
            let sensorData = SensorData(
                                id: UUID(),
                                source: "DOT",
                                startTimestamp: actualTimestamp,
                                stopTimestamp: nil,
                                accelerometer: AccelerometerData(
                                    x: Double(accX),
                                    y: Double(accY),
                                    z: Double(accZ),
                                    timestamp: actualTimestamp
                                ),
                                gyroscope: GyroscopeData(
                                    x: Double(gyroX),
                                    y: Double(gyroY),
                                    z: Double(gyroZ),
                                    timestamp: actualTimestamp
                                ),
                                eulerAngles: EulerAngles(
                                    roll: Double(roll),
                                    pitch: Double(pitch),
                                    yaw: Double(yaw)
                                ),
                                quaternion: Quaternion(
                                    w: Double(quatW),
                                    x: Double(quatX),
                                    y: Double(quatY),
                                    z: Double(quatZ)
                                )
                            )
            
            // 세션 저장
            DispatchQueue.main.async {
                sessionRef.dotSensorData.append(sensorData)
            }
            // 각 축별 데이터 전송 (롤, 피치, 요)
            let shortTimestamp = String(format: "%.3f", actualTimestamp.timeIntervalSince1970)
            // JSON payload로 전송 (type, deviceId 포함) - 기존 roll, pitch, yaw 재사용
            let messageDict: [String: Any] = [
                "type": "dotSensorData",
                "deviceId": wsPrefix,
                "timestamp": actualTimestamp.timeIntervalSince1970,
                "r": String(format: "%.2f", roll),
                "p": String(format: "%.2f", pitch),
                "y": String(format: "%.2f", yaw)
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: messageDict),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                CentralWebSocketManager.shared.send(jsonString)
            }
        }
        
        self.isRecording = true
        print("DOT RealTime 녹화 시작: \(device.uuid) - 모든 데이터 수집, Roll만 전송")
    }
        
    
    // DOT 실시간 녹화 중지
    func stopRealTimeRecording(for device: DotDevice) {
        device.plotMeasureEnable = false
        // use device.macAddress to match ContentView
        let cleanMAC = device.macAddress.replacingOccurrences(of: ":", with: "").uppercased()
        let macSuffix = String(cleanMAC.suffix(2))
        let fullKey = cleanMAC
        guard let session = activeSessions[fullKey] else { return }
        session.stopTimestamp = Date()
        CentralWebSocketManager.shared.send("DOT_SESSION_END")
        CentralWebSocketManager.shared.disconnect()
        DispatchQueue.main.async {
            self.sessionRecordings.append(session)
            print("DOT 세션 종료 및 저장: \(session.id)")
            if self.currentSession?.id == session.id {
                self.currentSession = nil
                self.isRecording = false
            }
            NotificationCenter.default.post(name: NSNotification.Name("SessionUpdated"), object: nil)
        }
        activeSessions.removeValue(forKey: fullKey)
        // ★ 연결 해제 시 매핑도 삭제
        deviceOrderMap.removeValue(forKey: device.uuid)
    }
}
