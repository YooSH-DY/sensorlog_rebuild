//// filepath: /Users/yoosehyeok/Documents/sensorlog_rebuild/sensorlog/RecordingDetailView.swift
import SwiftUI
// RecordingDetailView.swift (수정 예시)
struct RecordingDetailView: View {
    let session: SessionData
    let recording: SensorData
    
    func formattedTimestamp(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
            // 마이크로초 정밀도까지 표현 (소수점 이하 6자리)
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
            return formatter.string(from: date)
        }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("녹화 세션 상세")
                    .font(.largeTitle)
                    .bold()
                Text("세션 이름: \(session.name)")
                Text("Start Time: \(formattedTimestamp(recording.startTimestamp))")
                           if let stopTime = recording.stopTimestamp {
                               Text("End Time: \(formattedTimestamp(stopTime))")
                           } else {
                               Text("End Time: Ongoing")
                           }
                
                Text("전체 데이터 (\(session.allSensorData.count)건)")
                    .font(.headline)
                
                // 별도 섹션으로 표시하고 싶다면:
                if !session.watchSensorData.isEmpty {
                    Text("애플워치 데이터")
                        .font(.subheadline)
                    ForEach(session.watchSensorData, id: \.id) { data in
                        // 데이터를 필요한 방식으로 표시
                        Text("Accelerometer: \(data.accelerometer.x), \(data.accelerometer.y), \(data.accelerometer.z)")
                    }
                }
                if !session.dotSensorData.isEmpty {
                    Text("DOT 센서 데이터")
                        .font(.subheadline)
                    ForEach(session.dotSensorData, id: \.id) { data in
                        Text("Accelerometer: \(data.accelerometer.x), \(data.accelerometer.y), \(data.accelerometer.z)")
                        if let euler = data.eulerAngles {
                            Text("Euler Angles: \(euler.roll), \(euler.pitch), \(euler.yaw)")
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(formattedTimestamp(recording.startTimestamp))
        }
    }
}
