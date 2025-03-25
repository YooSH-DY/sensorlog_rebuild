//// filepath: /Users/yoosehyeok/Documents/sensorlog_rebuild/sensorlog/VisualizationViews.swift
import SwiftUI
import Charts

// 애플워치와 DOT 센서 자이로스코프 데이터를 각각 시각화하여 한 화면에 보여줍니다.
struct CombinedGyroscopeVisualizationView: View {
    let session: SessionData

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("애플워치 자이로스코프 데이터")
                    .font(.headline)
                Chart {
                    ForEach(session.watchSensorData) { data in
                        LineMark(
                            x: .value("Time", data.startTimestamp),
                            y: .value("X", data.gyroscope.x)
                        )
                        .foregroundStyle(.red)
                        LineMark(
                            x: .value("Time", data.startTimestamp),
                            y: .value("Y", data.gyroscope.y)
                        )
                        .foregroundStyle(.green)
                        LineMark(
                            x: .value("Time", data.startTimestamp),
                            y: .value("Z", data.gyroscope.z)
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .frame(height: 300)
                .padding()

                Text("DOT 센서 자이로스코프 데이터")
                    .font(.headline)
                Chart {
                    ForEach(session.dotSensorData) { data in
                        LineMark(
                            x: .value("Time", data.startTimestamp),
                            y: .value("X", data.gyroscope.x)
                        )
                        .foregroundStyle(.red)
                        LineMark(
                            x: .value("Time", data.startTimestamp),
                            y: .value("Y", data.gyroscope.y)
                        )
                        .foregroundStyle(.green)
                        LineMark(
                            x: .value("Time", data.startTimestamp),
                            y: .value("Z", data.gyroscope.z)
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .frame(height: 300)
                .padding()

                HStack(spacing: 20) {
                    LegendItem(color: .red, label: "X축")
                    LegendItem(color: .green, label: "Y축")
                    LegendItem(color: .blue, label: "Z축")
                }
            }
        }
        .navigationTitle("자이로스코프 시각화")
    }
}

// 애플워치와 DOT 센서 가속도계 데이터를 각각 시각화하여 한 화면에 보여줍니다.
struct CombinedAccelerometerVisualizationView: View {
    let session: SessionData

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("애플워치 가속도계 데이터")
                    .font(.headline)
                Chart {
                    ForEach(session.watchSensorData) { data in
                        LineMark(
                            x: .value("Time", data.startTimestamp),
                            y: .value("X", data.accelerometer.x)
                        )
                        .foregroundStyle(.red)
                        LineMark(
                            x: .value("Time", data.startTimestamp),
                            y: .value("Y", data.accelerometer.y)
                        )
                        .foregroundStyle(.green)
                        LineMark(
                            x: .value("Time", data.startTimestamp),
                            y: .value("Z", data.accelerometer.z)
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .frame(height: 300)
                .padding()

                Text("DOT 센서 가속도계 데이터")
                    .font(.headline)
                Chart {
                    ForEach(session.dotSensorData) { data in
                        LineMark(
                            x: .value("Time", data.startTimestamp),
                            y: .value("X", data.accelerometer.x)
                        )
                        .foregroundStyle(.red)
                        LineMark(
                            x: .value("Time", data.startTimestamp),
                            y: .value("Y", data.accelerometer.y)
                        )
                        .foregroundStyle(.green)
                        LineMark(
                            x: .value("Time", data.startTimestamp),
                            y: .value("Z", data.accelerometer.z)
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .frame(height: 300)
                .padding()

                HStack(spacing: 20) {
                    LegendItem(color: .red, label: "X축")
                    LegendItem(color: .green, label: "Y축")
                    LegendItem(color: .blue, label: "Z축")
                }
            }
        }
        .navigationTitle("가속도계 시각화")
    }
}

// 범례 아이템 컴포넌트는 기존과 동일합니다.
struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(color)
                .frame(width: 20, height: 2)
            Text(label)
                .font(.caption)
        }
    }
}
