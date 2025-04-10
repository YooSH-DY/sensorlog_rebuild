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
        var lastSendTime = Date()
        let minSendInterval: TimeInterval = 0.05  // 50ms마다 전송 (초당 20개로 제한)
        
        isRecording = true
        print("startRealTimeRecording 호출됨")
        
        // 샘플링 속도를 20Hz로 제한하여 안정성 향상
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        
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
            
            // 전송 간격 제한 - 너무 빈번한 전송 방지
            let now = Date()
            let elapsed = now.timeIntervalSince(lastSendTime)
            if elapsed < minSendInterval {
                return  // 최소 간격을 채우지 않았으면 건너뜀
            }
            
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
            
            // Yaw 값 계산 (쿼터니언에서 변환)
            let quaternion = motion.attitude.quaternion
            let yaw = self.calculateYaw(from: quaternion)
            
            // 최적화된 데이터 형식 - Yaw만 포함
            // 기존 메시지 형식과 호환되도록 구성
            let sensorDict: [String: Any] = [
                "type": "watchSensorData",
                "timestamp": (lastTimestamp ?? sensorTimestamp).timeIntervalSince1970,
                "yaw": Double(String(format: "%.2f", yaw)) ?? yaw
            ]
            
            // 메인 스레드에서 전송 (WCSession 요구사항)
            DispatchQueue.main.async {
                self.session.sendMessage(sensorDict, replyHandler: nil) { error in
                    print("워치 데이터 전송 오류: \(error.localizedDescription)")
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
            isRecording = false
            print("Watch RealTime Recording Stopped.")
        }
    
    func startRecording() {
        guard motionManager.isDeviceMotionAvailable else { return }
        isRecording = true
        recordedData.removeAll()
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0 //60hz

        // 기기 모션 데이터를 가져오기 위한 참조 프레임 설정
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
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
            
            // 쿼터니언 데이터 추가
            let quaternionData = Quaternion(
                w: motion.attitude.quaternion.w,
                x: motion.attitude.quaternion.x,
                y: motion.attitude.quaternion.y,
                z: motion.attitude.quaternion.z
            )

            // SensorData 객체 생성 (쿼터니언 포함)
            let data = SensorData(
                id: UUID(),
                startTimestamp: currentTimestamp,
                stopTimestamp: nil,
                accelerometer: accelerometerData,
                gyroscope: gyroscopeData,
                eulerAngles: nil,
                quaternion: quaternionData
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
