import SwiftUI
import MovellaDotSdk

// 기존의 SensorToggleButton은 그대로 사용합니다.
struct SensorToggleButton: View {
    var isOn: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut) {
                action()
            }
        }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isOn ? Color.green : Color.gray)
                    .frame(width: 60, height: 30)
                Circle()
                    .fill(Color.white)
                    .frame(width: 26, height: 26)
                    .padding(2)
                    .shadow(radius: 1)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// 센서 정보를 표시하는 행을 별도의 하위 뷰로 분리합니다.
struct SensorRowView: View {
    let device: DotDevice
    let isConnected: Bool
    let toggleAction: () -> Void
    
    // 센서의 이름을 표시 (주변기기 이름이 있으면 사용하고 없으면 UUID)
    var displayName: String {
        if let name = device.peripheral.name, !name.isEmpty {
            return name
        } else {
            return device.uuid
        }
    }
    
    // 배터리 정보를 포맷하여 생성: 연결되었을 경우 DotBatteryInfo의 value와 chargeState에 따라 표시
    var batteryInfo: String {
        guard isConnected, let battery = device.battery else {
            return "RSSI: \(device.rssi ?? 0) dBm"
        }
        let batteryText = "\(battery.value)%"
        if battery.chargeState {
            return "RSSI: \(device.rssi ?? 0) dBm / 배터리: \(batteryText) Charging"
        } else {
            return "RSSI: \(device.rssi ?? 0) dBm / 배터리: \(batteryText)"
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(displayName)")
                    .font(.subheadline)
                Text("MAC: \(device.macAddress)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                // 배터리 정보 텍스트를 출력. DeviceConnectCell.m에서는 연결된 경우에 배터리값과 충전여부를 표시합니다.
                Text(batteryInfo)
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
            Spacer()
            SensorToggleButton(isOn: isConnected, action: toggleAction)
        }
        .padding(.vertical, 4)
    }
}


// ContentView에서는 SensorRowView를 사용하여 ForEach 코드를 단순화합니다.
struct ContentView: View {
    @StateObject private var dataManager = PhoneDataManager.shared
    @StateObject private var dotManager = DotManager()
    @State private var isRecording = false
    @State private var selectedTab = "세션"
    // 기존 segmented picker를 왼쪽에 유지
    // 그리고 오른쪽에는 설정 버튼을 추가.
    @State private var showingSettings = false
    @StateObject private var recordingManager = DotRecordingManager()
    
    var body: some View {
        NavigationView {
            VStack {
                // 상단 탭 및 설정 버튼
                HStack {
                    Picker("", selection: $selectedTab) {
                        Text("DOT연결").tag("DOT연결")
                        Text("세션").tag("세션")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                    
                    Spacer()
                    
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                    }
                }
                .padding([.horizontal, .top])
                
                if selectedTab == "DOT연결" {
                    List {
                        ForEach(dotManager.discoveredDots, id: \.uuid) { device in
                            SensorRowView(
                                device: device,
                                isConnected: dotManager.connectedDots.contains(where: { $0.uuid == device.uuid }),
                                toggleAction: {
                                    if dotManager.connectedDots.contains(where: { $0.uuid == device.uuid }) {
                                        dotManager.disconnect(device: device)
                                    } else {
                                        dotManager.connect(to: device)
                                    }
                                }
                            )
                        }
                    }
                    .refreshable {
                        await dotManager.refreshScan()
                    }
                    .onAppear {
                        if !dotManager.isScanning {
                            Task { @MainActor in
                                dotManager.startScan()
                            }
                        }
                    }
                } else if selectedTab == "세션" {
                    RecordingsListView()
                }
                
                Spacer()
                
                // 녹화 버튼
                HStack {
                    Button(action: {
                        if isRecording {
                            // 녹화 정지
                            dataManager.sendWatchCommand(dataManager.recordingMode == .realtime ? "stop_realtime" : "stop")
                            if let device = dotManager.connectedDots.first {
                                if dataManager.recordingMode == .record {
                                    recordingManager.finishRecording(for: device)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                        dataManager.stopCurrentSession()
                                        print("Unified session 종료 (Record Mode)")
                                    }
                                } else { // realtime mode
                                    // DOT 센서는 별도 녹화 기능(청크)도 호출
                                    recordingManager.stopRealTimeRecording(for: device)
                                    RealTimeRecordingManager.shared.disconnect() {
                                        print("Realtime session 종료")
                                    }
                                    dataManager.stopCurrentSession()
                                }
                            }
                            isRecording = false
                        } else {
                            // 녹화 시작
                            dataManager.sendWatchCommand(dataManager.recordingMode == .realtime ? "start_realtime" : "start")
                            if let device = dotManager.connectedDots.first {
                                if dataManager.recordingMode == .record {
                                    recordingManager.startRecording(for: device)
                                    dataManager.startNewSession()
                                    print("Record Mode: 새로운 통합 세션 시작")
                                } else { // realtime mode
                                    // DOT 센서 녹화 기능(청크 방식)은 계속 호출 (필요한 경우)
                                    recordingManager.startRealTimeRecording(for: device)
                                    dataManager.startNewSession()
                                    // 실시간으로 애플워치 데이터 전송을 위해 RealTimeRecordingManager 연결
                                    RealTimeRecordingManager.shared.connect()
                                    print("Realtime Mode: 새로운 세션 시작 (실시간 전송)")
                                }
                            }
                            isRecording = true
                        }
                    }) {
                        Text(isRecording ? "녹화 정지" : "녹화 시작")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(isRecording ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView().environmentObject(dataManager)
            }
            .environmentObject(dataManager)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
