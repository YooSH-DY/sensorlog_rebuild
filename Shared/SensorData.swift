import Foundation

struct EulerAngles: Codable {
    let roll: Double
    let pitch: Double
    let yaw: Double
}
struct Quaternion: Codable {
    let w: Double
    let x: Double
    let y: Double
    let z: Double
}

struct SensorData: Codable, Identifiable {
    let id: UUID
    var source: String?
    let startTimestamp: Date
    var stopTimestamp: Date?
    let accelerometer: AccelerometerData
    let gyroscope: GyroscopeData
    let eulerAngles: EulerAngles? // 추가된 필드
    let quaternion: Quaternion? // 추가된 필드
}

struct AccelerometerData: Codable {
    let x: Double
    let y: Double
    let z: Double
    let timestamp: Date
}

struct GyroscopeData: Codable {
    let x: Double
    let y: Double
    let z: Double
    let timestamp: Date
}
