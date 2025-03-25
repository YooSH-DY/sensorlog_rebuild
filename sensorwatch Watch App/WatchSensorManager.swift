import Foundation
import CoreMotion
import WatchConnectivity

class WatchSensorManager: NSObject, ObservableObject {
    private var motionManager = CMMotionManager()
    private var session = WCSession.default
    @Published var isRecording = false
    // 녹화 모드(청크 방식)용 데이터 저장 배열
    private var recordedData = [SensorData]()
    private let chunkSize = 50  // 한 번에 전송할 데이터 개수
    private let maxRetries = 3
    private let retryDelay = 0.5
    private let chunkDelay = 0.3
    
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
    
    // 리얼타임 모드: 센서 데이터 업데이트마다 바로 전송
    func startRealTimeRecording() {
        print("워치에서 startRealTimeRecording 호출됨")
        guard motionManager.isDeviceMotionAvailable else {
            print("DeviceMotion 지원 안됨")
            return
        }
        
        // 부팅 시간 계산 (현재 시간 - systemUptime)
        let bootTimeInterval = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        var lastTimestamp: Date?
        
        isRecording = true
        print("startRealTimeRecording 호출됨")
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0 // 60Hz
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            if let error = error {
                print("Motion 업데이트 오류: \(error.localizedDescription)")
            }
            guard let self = self, let motion = motion else { return }
            
            // CoreMotion의 timestamp를 실제 시간으로 변환
            let motionTimestamp = bootTimeInterval + motion.timestamp
            let sensorTimestamp = Date(timeIntervalSince1970: motionTimestamp)
            
            // 중복 타임스탬프 방지
            if let last = lastTimestamp, sensorTimestamp <= last {
                let adjustedTimestamp = last.addingTimeInterval(0.001)
                lastTimestamp = adjustedTimestamp
                print("⚠️ 타임스탬프 중복 조정됨")
            } else {
                lastTimestamp = sensorTimestamp
            }
            
            print("워치 실시간 센서 데이터 업데이트: \(motion.rotationRate)")
            
            let sensorDict: [String: Any] = [
                "type": "watchSensorData",
                "timestamp": (lastTimestamp ?? sensorTimestamp).timeIntervalSince1970,
                "accX": motion.userAcceleration.x,
                "accY": motion.userAcceleration.y,
                "accZ": motion.userAcceleration.z,
                "gyroX": motion.rotationRate.x,
                "gyroY": motion.rotationRate.y,
                "gyroZ": motion.rotationRate.z
            ]
            
            self.session.sendMessage(sensorDict, replyHandler: nil) { error in
                print("리얼타임 전송 오류: \(error.localizedDescription)")
            }
        }
    }
        func stopRealTimeRecording() {
            motionManager.stopDeviceMotionUpdates()
            isRecording = false
            print("Watch RealTime Recording Stopped.")
        }
    
    func startRecording() {
        guard motionManager.isDeviceMotionAvailable else { return }
        isRecording = true
        recordedData.removeAll()
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0 //60hz
        //motionManager.deviceMotionUpdateInterval = 0.01 // 100Hz

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }

            let currentTimestamp = Date()

            // AccelerometerData 생성
            let accelerometerData = AccelerometerData(
                x: motion.userAcceleration.x,
                y: motion.userAcceleration.y,
                z: motion.userAcceleration.z,
                timestamp: currentTimestamp
            )

            // GyroscopeData 생성
            let gyroscopeData = GyroscopeData(
                x: motion.rotationRate.x,
                y: motion.rotationRate.y,
                z: motion.rotationRate.z,
                timestamp: currentTimestamp
            )

            // SensorData 객체 생성
            let data = SensorData(
                id: UUID(),
                startTimestamp: currentTimestamp,
                stopTimestamp: nil,
                accelerometer: accelerometerData,
                gyroscope: gyroscopeData,
                eulerAngles: nil,
                quaternion : nil
            )

            self.recordedData.append(data)
        }
    }

    func stopRecording() {
        isRecording = false
        motionManager.stopDeviceMotionUpdates()

        // 종료 시간 업데이트
        if let lastIndex = recordedData.indices.last {
            recordedData[lastIndex].stopTimestamp = Date()
        }

        sendRecordedDataInChunks()
    }

    private func sendRecordedDataInChunks() {
        print("전체 데이터 개수: \(recordedData.count)")
        
        // 데이터를 청크로 나누기
        let chunks = stride(from: 0, to: recordedData.count, by: chunkSize).map {
            Array(recordedData[$0..<min($0 + chunkSize, recordedData.count)])
        }
        
        // 각 청크에 대해
        for (index, chunk) in chunks.enumerated() {
            do {
                let jsonData = try JSONEncoder().encode(chunk)
                let jsonString = jsonData.base64EncodedString()
                
                // 메시지에 청크 정보 포함
                let message: [String: Any] = [
                    "data": jsonString,
                    "chunkIndex": index,
                    "totalChunks": chunks.count,
                    "isLastChunk": index == chunks.count - 1
                ]
                
                session.sendMessage(message, replyHandler: nil) { error in
                    print("청크 \(index + 1)/\(chunks.count) 전송 실패:", error.localizedDescription)
                }
                
                print("청크 \(index + 1)/\(chunks.count) 전송됨 (크기: \(chunk.count))")
                
                // 청크 사이에 약간의 딜레이를 줌
                Thread.sleep(forTimeInterval: 0.1)
            } catch {
                print("JSON 인코딩 실패:", error.localizedDescription)
            }
        }
    }
}

extension WatchSensorManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let command = message["command"] as? String {
            print("워치에서 수신한 명령: \(command)")
            DispatchQueue.main.async {
                if command == "start" {
                    // 녹화 모드: 청크 방식 사용
                    self.startRecording()
                } else if command == "stop" {
                    self.stopRecording()
                } else if command == "start_realtime" {
                    // 리얼타임 모드: 실시간 전송 방식 사용
                    self.startRealTimeRecording()
                } else if command == "stop_realtime" {
                    self.stopRealTimeRecording()
                } else {
                    print("알 수 없는 명령: \(command)")
                }
            }
        }
    }
}
