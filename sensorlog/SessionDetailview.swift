import SwiftUI

struct SessionDetailView: View {
    @ObservedObject var session: SessionData
    
    // 밀리초까지 표시하는 DateFormatter
    private var customFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }
    
    @State private var isWatchDataExpanded = false
    @State private var isDotDataExpanded = false
    
    var body: some View {
        List {
            // 기본 정보 섹션
            Section(header: Text("기본 정보")) {
                HStack {
                    Text("세션 이름")
                    Spacer()
                    Text(session.name)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("시작 시간")
                    Spacer()
                    Text(customFormatter.string(from: session.startTimestamp))
                        .foregroundColor(.secondary)
                }
                if let stopTime = session.stopTimestamp {
                    HStack {
                        Text("종료 시간")
                        Spacer()
                        Text(customFormatter.string(from: stopTime))
                            .foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text("전체 데이터 수")
                    Spacer()
                    Text("\(session.allSensorData.count)건")
                        .foregroundColor(.secondary)
                }
            }
            
            // 애플워치 데이터 섹션
            Section(header: Text("애플워치 데이터 (\(session.watchSensorData.count)건)")) {
                Button(action: {
                    withAnimation {
                        isWatchDataExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text("애플워치 데이터")
                        Spacer()
                        Image(systemName: isWatchDataExpanded ? "chevron.up" : "chevron.down")
                    }
                }
                
                if isWatchDataExpanded {
                    if session.watchSensorData.isEmpty {
                        Text("애플워치 데이터가 없습니다")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(session.watchSensorData) { data in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("시간: \(customFormatter.string(from: data.startTimestamp))")
                                    .font(.caption)
                                Text("가속도계 - X: \(data.accelerometer.x), Y: \(data.accelerometer.y), Z: \(data.accelerometer.z)")
                                    .font(.caption2)
                                Text("자이로스코프 - X: \(data.gyroscope.x), Y: \(data.gyroscope.y), Z: \(data.gyroscope.z)")
                                    .font(.caption2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            
            // DOT 센서 데이터 섹션
            Section(header: Text("DOT 센서 데이터 (\(session.dotSensorData.count)건)")) {
                Button(action: {
                    withAnimation {
                        isDotDataExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text("DOT 센서 데이터")
                        Spacer()
                        Image(systemName: isDotDataExpanded ? "chevron.up" : "chevron.down")
                    }
                }
                
                if isDotDataExpanded {
                    if session.dotSensorData.isEmpty {
                        Text("DOT 센서 데이터가 없습니다")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(session.dotSensorData) { data in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("시간: \(customFormatter.string(from: data.startTimestamp))")
                                    .font(.caption)
                                Text("가속도계 - X: \(data.accelerometer.x), Y: \(data.accelerometer.y), Z: \(data.accelerometer.z)")
                                    .font(.caption2)
                                Text("자이로스코프 - X: \(data.gyroscope.x), Y: \(data.gyroscope.y), Z: \(data.gyroscope.z)")
                                    .font(.caption2)
                                if let quaternion = data.quaternion {
                                    Text("쿼터니언 - W: \(quaternion.w), X: \(quaternion.x), Y: \(quaternion.y), Z: \(quaternion.z)")
                                        .font(.caption2)
                                }
                                if let euler = data.eulerAngles {
                                    Text("오일러 - Roll: \(euler.roll), Pitch: \(euler.pitch), Yaw: \(euler.yaw)")
                                        .font(.caption2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("녹화 세션 상세")
    }
}
