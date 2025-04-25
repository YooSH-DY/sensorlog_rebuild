import Foundation
import CoreMotion
import WatchConnectivity
import WatchKit

class WatchSensorManager: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
    // Xcode가 추가한 메서드 (올바른 시그니처)
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?) {
        print("ExtendedRuntimeSession 종료됨, 이유: \(reason)")
        if let error = error {
            print("종료 오류: \(error.localizedDescription)")
        }
        stopRealTimeRecording() // 기존 로직 유지
    }
    private var motionManager = CMMotionManager()
    private var session = WCSession.default
    private var runtimeSession: WKExtendedRuntimeSession?
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
    // WKExtendedRuntimeSessionDelegate 필수 메서드들 다시 구현
        func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
            print("ExtendedRuntimeSession 시작됨")
            startRealTimeRecording()
        }
        
        func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
            print("ExtendedRuntimeSession 만료 임박")
        }
        
    private func setupWCSession() {
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
            print("워치: WCSession 활성화 시도")
        } else {
            print("워치: WCSession이 지원되지 않음")
        }
    }
    
    // 리얼타임 모드: 센서 데이터 업데이트마다 바로 전송
    func startRealTimeRecording() {
        print("워치에서 startRealTimeRecording 호출됨")
        guard motionManager.isDeviceMotionAvailable else {
            print("DeviceMotion 지원 안됨")
            return
        }
        // @Published 속성은 메인 스레드에서 변경
        DispatchQueue.main.async {
            self.isRecording = true
            // recordedData도 메인 스레드에서 변경해야 함
            self.recordedData.removeAll()
        }
        // 부팅 시간 계산 (현재 시간 - systemUptime)
        let bootTimeInterval = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        var lastTimestamp: Date?
        var lastSendTime = Date()
        //let minSendInterval: TimeInterval = 0.05  // 50ms마다 전송 (초당 20개로 제한)
        
        
        // 리얼타임모드 웹소켓전송 속도 이거임
        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0
        
        // 전용 처리 큐 설정
        let motionQueue = OperationQueue()
        motionQueue.maxConcurrentOperationCount = 1
        motionQueue.qualityOfService = .userInitiated
        
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self = self,
                  let motion = motion,
                  error == nil else {
                if let error = error {
                    print("Motion 업데이트 오류: \(error.localizedDescription)")
                }
                return
            }
            // isRecording 확인을 위한 로컬 변수 사용
            var shouldProcess = false
            DispatchQueue.main.sync {
                shouldProcess = self.isRecording
            }
            
            guard shouldProcess else { return }
            
            // 전송 간격 제한 - 너무 빈번한 전송 방지
            let now = Date()
            let elapsed = now.timeIntervalSince(lastSendTime)
            
            // CoreMotion의 timestamp를 실제 시간으로 변환
            let motionTimestamp = bootTimeInterval + motion.timestamp
            let sensorTimestamp = Date(timeIntervalSince1970: motionTimestamp)
            
            // 중복 타임스탬프 방지
            if let last = lastTimestamp, sensorTimestamp <= last {
                let adjustedTimestamp = last.addingTimeInterval(0.001)
                lastTimestamp = adjustedTimestamp
            } else {
                lastTimestamp = sensorTimestamp
            }
            
            lastSendTime = now
            
            // 모든 센서 데이터 수집
            // 1. 가속도 데이터
            let userAccel = motion.userAcceleration
            let accX = userAccel.x
            let accY = userAccel.y
            let accZ = userAccel.z
            
            // 2. 자이로스코프 데이터
            let rotationRate = motion.rotationRate
            let gyroX = rotationRate.x
            let gyroY = rotationRate.y
            let gyroZ = rotationRate.z
            
            // 3. 오일러 각도 계산
            let attitude = motion.attitude
            let roll = attitude.roll * (180.0 / .pi)
            let pitch = attitude.pitch * (180.0 / .pi)
            let yaw = attitude.yaw * (180.0 / .pi)
            
            // 4. 쿼터니언 데이터
            let quat = motion.attitude.quaternion
            let quatW = quat.w
            let quatX = quat.x
            let quatY = quat.y
            let quatZ = quat.z
            
            // 로그 추가: 수집된 센서 데이터 출력
//            print("""
//            [워치 실시간] \(sensorTimestamp)
//            acc: (\(String(format: "%.3f", accX)), \(String(format: "%.3f", accY)), \(String(format: "%.3f", accZ)))
//            gyro: (\(String(format: "%.3f", gyroX)), \(String(format: "%.3f", gyroY)), \(String(format: "%.3f", gyroZ)))
//            euler: (roll: \(String(format: "%.2f", roll)), pitch: \(String(format: "%.2f", pitch)), yaw: \(String(format: "%.2f", yaw)))
//            quat: (w: \(String(format: "%.3f", quatW)), x: \(String(format: "%.3f", quatX)), y: \(String(format: "%.3f", quatY)), z: \(String(format: "%.3f", quatZ)))
//            """)
            
            // 전체 센서 데이터 딕셔너리 생성 (로컬 저장용)
            let fullSensorDict: [String: Any] = [
                "type": "watchSensorDataFull",
                "timestamp": (lastTimestamp ?? sensorTimestamp).timeIntervalSince1970,
                "accX": accX, "accY": accY, "accZ": accZ,
                "gyroX": gyroX, "gyroY": gyroY, "gyroZ": gyroZ,
                "roll": roll, "pitch": pitch, "yaw": yaw,
                "quatW": quatW, "quatX": quatX, "quatY": quatY, "quatZ": quatZ
            ]
            
            // 웹소켓 전송용 간소화된 메시지 (Yaw만 포함)
            let transmitDict: [String: Any] = [
                "type": "watchSensorData",
                "timestamp": (lastTimestamp ?? sensorTimestamp).timeIntervalSince1970,
                "yaw": Double(String(format: "%.2f", yaw)) ?? yaw
            ]
            
            // 메인 스레드에서 전송 (WCSession 요구사항)
            DispatchQueue.main.async {
                guard self.session.isReachable else {
                        print("📴 iPhone Unreachable: 메세지 버퍼링 또는 재시도")
                        return
                    }
                // 전체 데이터는 로컬 저장을 위해 전송
                self.session.sendMessage(fullSensorDict, replyHandler: nil) { error in
                    print("워치 전체 데이터 전송 오류: \(error.localizedDescription)")
                }
                
                // 최적화된 데이터는 웹소켓 전송용으로만 사용
                self.session.sendMessage(transmitDict, replyHandler: nil) { error in
                    print("워치 간소화 데이터 전송 오류: \(error.localizedDescription)")
                }
            }
        }
    }

    // Yaw 값만 계산하는 헬퍼 함수 추가
    private func calculateYaw(from quaternion: CMQuaternion) -> Double {
        let w = quaternion.w
        let x = quaternion.x
        let y = quaternion.y
        let z = quaternion.z
        
        // 요(Yaw) 계산 (z-축 회전)
        let yaw = atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))
        
        // 라디안에서 각도로 변환
        return yaw * (180.0 / .pi)
    }
    func stopRealTimeRecording() {
        motionManager.stopDeviceMotionUpdates()
        // 메인 스레드에서 속성 업데이트
        DispatchQueue.main.async {
            self.isRecording = false
        }
        print("Watch RealTime Recording Stopped.")
    }
    
    func startRecording() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        // 메인 스레드에서 속성 업데이트
        DispatchQueue.main.async {
            self.isRecording = true
            self.recordedData.removeAll()
        }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0 //60hz

        // 전용 큐 사용
        let motionQueue = OperationQueue()
        motionQueue.maxConcurrentOperationCount = 1
        motionQueue.qualityOfService = .userInitiated

        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }

            let currentTimestamp = Date()

            // 모든 데이터 수집
            let accelerometerData = AccelerometerData(
                x: motion.userAcceleration.x,
                y: motion.userAcceleration.y,
                z: motion.userAcceleration.z,
                timestamp: currentTimestamp
            )

            let gyroscopeData = GyroscopeData(
                x: motion.rotationRate.x,
                y: motion.rotationRate.y,
                z: motion.rotationRate.z,
                timestamp: currentTimestamp
            )
            
            let quaternionData = Quaternion(
                w: motion.attitude.quaternion.w,
                x: motion.attitude.quaternion.x,
                y: motion.attitude.quaternion.y,
                z: motion.attitude.quaternion.z
            )

            let data = SensorData(
                id: UUID(),
                startTimestamp: currentTimestamp,
                stopTimestamp: nil,
                accelerometer: accelerometerData,
                gyroscope: gyroscopeData,
                eulerAngles: nil,
                quaternion: quaternionData
            )

            // 메인 스레드에서 UI 업데이트
            DispatchQueue.main.async {
                self.recordedData.append(data)
            }
        }
    }

    func stopRecording() {
        // 메인 스레드에서 속성 업데이트
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        motionManager.stopDeviceMotionUpdates()

        // 종료 시간 업데이트
        DispatchQueue.main.async {
            if let lastIndex = self.recordedData.indices.last {
                self.recordedData[lastIndex].stopTimestamp = Date()
            }
            self.sendRecordedDataInChunks()
        }
    }

    private func sendRecordedDataInChunks() {
        print("전체 데이터 개수: \(recordedData.count)")
        
        // 데이터를 청크로 나누기
        let chunks = stride(from: 0, to: recordedData.count, by: chunkSize).map {
            Array(recordedData[$0..<min($0 + chunkSize, recordedData.count)])
        }
        
        // 청크 전송을 위한 큐 생성
        let sendQueue = DispatchQueue(label: "com.sensorlog.chunksend", qos: .userInitiated)
        
        // 각 청크의 전송 상태를 추적
        var sentChunks = [Bool](repeating: false, count: chunks.count)
        let group = DispatchGroup()
        
        // 각 청크에 대해
        for (index, chunk) in chunks.enumerated() {
            group.enter()
            sendQueue.async {
                self.sendChunk(chunk, index: index, totalChunks: chunks.count, retryCount: 0) { success in
                    sentChunks[index] = success
                    group.leave()
                }
            }
            
            // 청크 사이에 딜레이를 주되, 스레드 차단 없이
            if index < chunks.count - 1 {
                sendQueue.asyncAfter(deadline: .now() + self.chunkDelay) { }
            }
        }
        
        // 모든 청크 전송 완료 후 결과 확인
        group.notify(queue: .main) {
            let failedChunks = sentChunks.enumerated().filter { !$0.element }.map { $0.offset }
            if failedChunks.isEmpty {
                print("모든 청크가 성공적으로 전송되었습니다.")
            } else {
                print("전송 실패한 청크: \(failedChunks)")
            }
        }
    }

    private func sendChunk(_ chunk: [SensorData], index: Int, totalChunks: Int, retryCount: Int, completion: @escaping (Bool) -> Void) {
        do {
            let jsonData = try JSONEncoder().encode(chunk)
            let jsonString = jsonData.base64EncodedString()
            
            // 메시지에 청크 정보 포함
            let message: [String: Any] = [
                "data": jsonString,
                "chunkIndex": index,
                "totalChunks": totalChunks,
                "isLastChunk": index == totalChunks - 1
            ]
            
            session.sendMessage(message, replyHandler: { _ in
                print("청크 \(index + 1)/\(totalChunks) 전송 성공 (크기: \(chunk.count))")
                completion(true)
            }) { error in
                print("청크 \(index + 1)/\(totalChunks) 전송 실패: \(error.localizedDescription)")
                
                // 재시도 로직
                if retryCount < self.maxRetries {
                    print("청크 \(index + 1)/\(totalChunks) 재시도 \(retryCount + 1)/\(self.maxRetries)")
                    
                    // 재시도 전 딜레이
                    DispatchQueue.global().asyncAfter(deadline: .now() + self.retryDelay) {
                        self.sendChunk(chunk, index: index, totalChunks: totalChunks, retryCount: retryCount + 1, completion: completion)
                    }
                } else {
                    print("청크 \(index + 1)/\(totalChunks) 최대 재시도 횟수 초과")
                    completion(false)
                }
            }
        } catch {
            print("JSON 인코딩 실패: \(error.localizedDescription)")
            completion(false)
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
