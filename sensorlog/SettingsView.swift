//// filepath: /Users/yoosehyeok/Documents/sensorlog_rebuild/sensorlog/SettingsView.swift
import SwiftUI

enum RecordMode: String, CaseIterable, Identifiable {
    case record = "Record Mode"
    case realtime = "Realtime Mode"
    
    var id: String { self.rawValue }
}

struct SettingsView: View {
    @EnvironmentObject var dataManager: PhoneDataManager
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("녹화 모드 선택")) {
                    Picker("모드 선택", selection: $dataManager.recordingMode) {
                        ForEach(RecordMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("설정")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
