//// filepath: /Users/yoosehyeok/Documents/sensorlog_rebuild/sensorlog/SessionData.swift
import Foundation

class SessionData: Identifiable, ObservableObject {
    let id: UUID
    @Published var name: String
    let startTimestamp: Date
    var stopTimestamp: Date?
    
    // 별도 저장: 애플워치 센서 데이터와 DOT 센서 데이터
    @Published var watchSensorData: [SensorData]
    @Published var dotSensorData: [SensorData]
    
    // 전체 센서 데이터를 합친 배열 (타임스탬프 기준 정렬)
    var allSensorData: [SensorData] {
        return (watchSensorData + dotSensorData).sorted { $0.startTimestamp < $1.startTimestamp }
    }
    
    init(id: UUID = UUID(), name: String? = nil, startTimestamp: Date, stopTimestamp: Date? = nil, watchSensorData: [SensorData] = [], dotSensorData: [SensorData] = []) {
        self.id = id
        self.name = name ?? "세션 \(id.uuidString.prefix(8))"
        self.startTimestamp = startTimestamp
        self.stopTimestamp = stopTimestamp
        self.watchSensorData = watchSensorData
        self.dotSensorData = dotSensorData
    }
}
