import Foundation
import MovellaDotSdk

struct DOTSensorData: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let roll: Double
    let pitch: Double
    let yaw: Double
    let quatW: Double
    let quatX: Double
    let quatY: Double
    let quatZ: Double
    let accX: Double
    let accY: Double
    let accZ: Double
    let gyroX: Double
    let gyroY: Double
    let gyroZ: Double

    init(id: UUID = UUID(), timestamp: Date, eulerAngles: (Double, Double, Double), quaternion: (Double, Double, Double, Double), acceleration: (Double, Double, Double), gyro: (Double, Double, Double)) {
        self.id = id
        self.timestamp = timestamp
        self.roll = eulerAngles.0
        self.pitch = eulerAngles.1
        self.yaw = eulerAngles.2
        self.quatW = quaternion.0
        self.quatX = quaternion.1
        self.quatY = quaternion.2
        self.quatZ = quaternion.3
        self.accX = acceleration.0
        self.accY = acceleration.1
        self.accZ = acceleration.2
        self.gyroX = gyro.0
        self.gyroY = gyro.1
        self.gyroZ = gyro.2
    }
}

struct DOTSessionData: Identifiable, Codable {
    let id: UUID
    let name: String
    let startTimestamp: Date
    let stopTimestamp: Date?
    let sensorData: [DOTSensorData]
    
    init(id: UUID = UUID(), name: String, startTimestamp: Date, stopTimestamp: Date? = nil, sensorData: [DOTSensorData] = []) {
        self.id = id
        self.name = name
        self.startTimestamp = startTimestamp
        self.stopTimestamp = stopTimestamp
        self.sensorData = sensorData
    }
}
// DOT 녹화 및 실시간 전송 기능 (기존 코드에 실시간 전송 추가)
class DotRecordingManager: ObservableObject {
    @Published var isRecording = false
    private var recordedData: [String: [RecordingData]] = [:]
    // 마지막 전송한 결합 CSV 행 저장 (중복 방지 용도)
    private var lastCombinedCSVRow: String?
    
    struct RecordingData {
        let timestamp: TimeInterval  // 마이크로초 단위
        let eulerAngles: (Double, Double, Double)
        let quaternion: (Double, Double, Double, Double)
        let acceleration: (Double, Double, Double)
        let gyro: (Double, Double, Double)
    }
    
    // 기존 녹화 모드 (레코딩) 메소드 – 청크 전송 후 머지
    func startRecording(for device: DotDevice) {
        device.setOutputRate(20, filterIndex: 0)
        device.plotMeasureMode = .customMode4
        device.plotMeasureEnable = true
        recordedData[device.uuid] = []
        
        device.setDidParsePlotDataBlock { [weak self] plotData in
            guard let self = self else { return }
            var euler = [0.0, 0.0, 0.0]
            DotUtils.quat(toEuler: &euler,
                          withW: plotData.quatW,
                          withX: plotData.quatX,
                          withY: plotData.quatY,
                          withZ: plotData.quatZ)
            let rawTimestamp = Date().timeIntervalSince1970
            let dataPoint = RecordingData(
                timestamp: rawTimestamp * 1_000_000.0,
                eulerAngles: (euler[0], euler[1], euler[2]),
                quaternion: (Double(plotData.quatW), Double(plotData.quatX), Double(plotData.quatY), Double(plotData.quatZ)),
                acceleration: (plotData.acc0, plotData.acc1, plotData.acc2),
                gyro: (plotData.gyr0, plotData.gyr1, plotData.gyr2)
            )
            DispatchQueue.main.async {
                self.recordedData[device.uuid, default: []].append(dataPoint)
            }
            let csvRow = "\(rawTimestamp),,,,,,," +
            "\(plotData.acc0),\(plotData.acc1),\(plotData.acc2)," +
            "\(plotData.gyr0),\(plotData.gyr1),\(plotData.gyr2)," +
            "\(euler[0]),\(euler[1]),\(euler[2])," +
            "\(plotData.quatW),\(plotData.quatX),\(plotData.quatY),\(plotData.quatZ)\n"
            RealTimeRecordingManager.shared.sendMessage(csvRow)
        }
        isRecording = true
        print("DOT 녹화 시작 (레코딩 모드): \(device.uuid)")
    }
    
    func stopRecording(for device: DotDevice) {
        device.plotMeasureEnable = false
        isRecording = false
        print("DOT 녹화 종료 (레코딩 모드): \(device.uuid)")
    }
    
    func finishRecording(for device: DotDevice) {
        stopRecording(for: device)
        
        guard let recordings = recordedData[device.uuid], !recordings.isEmpty else {
            print("녹화된 데이터가 없습니다.")
            return
        }
        
        let sensorDatas = recordings.map { rec -> DOTSensorData in
            return DOTSensorData(
                timestamp: Date(timeIntervalSince1970: rec.timestamp / 1_000_000.0),
                eulerAngles: rec.eulerAngles,
                quaternion: rec.quaternion,
                acceleration: rec.acceleration,
                gyro: rec.gyro
            )
        }
        
        let startTime = sensorDatas.first?.timestamp ?? Date()
        let stopTime = sensorDatas.last?.timestamp
        
        let dotSession = DOTSessionData(
            id: UUID(),
            name: "DOT 녹화 \(device.uuid.prefix(8))",
            startTimestamp: startTime,
            stopTimestamp: stopTime,
            sensorData: sensorDatas
        )
        
        PhoneDataManager.shared.mergeDOTSession(with: dotSession)
        print("DOT 녹화 세션 병합 완료 (레코딩 모드): \(dotSession.id)")
    }
    
    // ─────────────────────────────────────────────
    func startRealTimeRecording(for device: DotDevice) {
        device.setOutputRate(30, filterIndex: 0)
        device.plotMeasureMode = .customMode4
        device.plotMeasureEnable = true
        
        // 첫 데이터 수신 시점의 기준 시간 저장
        let sessionStartTime = Date()
        var firstSampleTime: UInt32? = nil
        
        // 별도의 전용 큐에서 DOT 센서 데이터를 처리
        let dotQueue = DispatchQueue(label: "com.yourapp.dotSensorQueue", qos: .userInitiated)
        device.setDidParsePlotDataBlock { [weak self] plotData in
            dotQueue.async { [weak self] in
                guard let self = self else { return }
                
                // 센서의 상대적 타임스탬프를 현재 시간 기준으로 변환
                let currentDate = Date()
                
                // 첫 번째 샘플 시간을 기준으로 상대적인 시간 계산
                if firstSampleTime == nil {
                    firstSampleTime = plotData.timeStamp
                }
                
                // 상대적 시간 차이 계산 (마이크로초 → 초 변환)
                let timeOffset = Double(plotData.timeStamp - (firstSampleTime ?? plotData.timeStamp)) / 1_000_000.0
                
                // 세션 시작 시간에 상대적 오프셋을 더해서 실제 타임스탬프 계산
                let actualTimestamp = sessionStartTime.addingTimeInterval(timeOffset)
                
                // 타임스탬프를 한국 시간(KST)으로 포맷팅
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
                formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
                let dotTimestamp = formatter.string(from: actualTimestamp)
                
                // 오일러 각 계산 (Quat -> Euler 변환)
                var euler: [Double] = [0.0, 0.0, 0.0]
                DotUtils.quat(toEuler: &euler,
                              withW: plotData.quatW,
                              withX: plotData.quatX,
                              withY: plotData.quatY,
                              withZ: plotData.quatZ)
                
                // Roll 값만 추출 (euler[0]이 Roll 값)
                let roll = euler[0]
                
                // Roll 값만 포함하는 CSV 행 생성
                let dotCSVRow = "\(dotTimestamp),\(roll)\n"
                
                // 최적화된 웹소켓 전송 문자열
                // t=timestamp, r=roll
                let shortTimestamp = String(format: "%.3f", actualTimestamp.timeIntervalSince1970)
                let optimizedRow = "t:\(shortTimestamp),r:\(roll)"
                
                // 메시지 전송
                RealTimeRecordingManager.shared.sendDotMessage("DOT:" + optimizedRow)
            }
        }
        self.isRecording = true
        print("DOT RealTime 녹화 시작: \(device.uuid) - Roll만 전송")
    }
    
    func stopRealTimeRecording(for device: DotDevice) {
        device.plotMeasureEnable = false
        self.isRecording = false
        print("DOT RealTime 녹화 종료: \(device.uuid)")
    }
    // DotRecording.swift 수정
    private let dotSendQueue = DispatchQueue(label: "com.dot.sendQueue", qos: .userInteractive)
    
    func sendDOTData(_ csvRow: String) {
        dotSendQueue.async {
            RealTimeRecordingManager.shared.sendMessage("DOT:" + csvRow)
        }
    }
}
