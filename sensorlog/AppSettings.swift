//// filepath: /Users/yoosehyeok/Documents/sensorlog_rebuild/sensorlog/AppSettings.swift
import SwiftUI

enum SensorMode: String, CaseIterable, Identifiable, Codable {
    case streaming = "Streaming"
    case recording = "Recording"
    var id: String { rawValue }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    @Published var sensorMode: SensorMode = .streaming
}