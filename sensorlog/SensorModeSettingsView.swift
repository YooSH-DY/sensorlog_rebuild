//// filepath: /Users/yoosehyeok/Documents/sensorlog_rebuild/sensorlog/SensorModeSettingsView.swift
import SwiftUI

struct SensorModeSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Picker("센서 모드 선택", selection: $settings.sensorMode) {
                    ForEach(SensorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .navigationBarTitle("설정", displayMode: .inline)
            .navigationBarItems(trailing: Button("닫기") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}