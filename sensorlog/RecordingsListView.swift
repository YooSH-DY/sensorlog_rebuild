import SwiftUI
import Foundation

struct RecordingsListView: View {
    @EnvironmentObject var dataManager: PhoneDataManager
    @State private var selectedSessions: Set<UUID> = []
    @State private var showingExportOptions = false
    @State private var showingMultipleExportView = false  // 다중 세션 내보내기 뷰 표시 여부
    @State private var sensorDatasToExport: [SensorData] = []
    @State private var isSelectionMode: Bool = false
    @State private var localEditMode: EditMode = .inactive  // 별도 상태 변수
    @State private var showingRealtimeGraph = false  // 실시간 그래프 표시 여부

    func calculateDuration(session: SessionData) -> String {
        let endTime = session.stopTimestamp ?? Date()
        let duration = endTime.timeIntervalSince(session.startTimestamp)
        return String(format: "%.1f초", duration)
    }
    
    var body: some View {
        NavigationView {
            VStack {
//                // 실시간 쿼터니언 버튼
//                Button(action: {
//                    showingRealtimeGraph = true
//                }) {
//                    HStack {
//                        Image(systemName: "waveform.path.ecg")
//                        Text("실시간 쿼터니언 데이터 보기")
//                    }
//                    .frame(maxWidth: .infinity)
//                    .padding()
//                    .background(Color.blue)
//                    .foregroundColor(.white)
//                    .cornerRadius(8)
//                }
//                .padding(.horizontal)
//                .padding(.top, 8)
//                
                // 기존 리스트 내용
                List(selection: $selectedSessions) {
                    if isSelectionMode {
                        ForEach(dataManager.sessionRecordings) { session in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(session.name)
                                        .font(.headline)
                                    Text("데이터 수: \(session.allSensorData.count)")
                                        .font(.subheadline)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .tag(session.id)
                        }
                    } else {
                        ForEach(dataManager.sessionRecordings) { session in
                            NavigationLink(destination: SessionOptionsView(session: session)) {
                                VStack(alignment: .leading) {
                                    Text(session.name)
                                        .font(.headline)
                                    Text("데이터 수: \(session.allSensorData.count)")
                                        .font(.subheadline)
                                }
                            }
                        }
                        .onDelete(perform: deleteSessions)
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("세션")
            .environment(\.editMode, $localEditMode)
            .toolbar {
                if isSelectionMode {
                    // 왼쪽에 공유 버튼: 선택한 세션들로 다중 세션 내보내기 뷰 호출
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            showingMultipleExportView = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    // 오른쪽에 "취소" 버튼
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("취소") {
                            withAnimation {
                                isSelectionMode = false
                                localEditMode = .inactive
                                selectedSessions.removeAll()
                            }
                        }
                    }
                } else {
                    // 일반 모드: 오른쪽에 "선택" 버튼
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("선택") {
                            withAnimation {
                                isSelectionMode = true
                                localEditMode = .active
                            }
                        }
                    }
                }
            }
        }
        // 실시간 그래프 시트
        .sheet(isPresented: $showingRealtimeGraph) {
            RealtimeGraphView()
                .environmentObject(dataManager)
        }
        // 기존 CSV 내보내기 시트
        .sheet(isPresented: $showingExportOptions) {
            ShareSheet(activityItems: sensorDatasToExport)
        }
        // 다중 세션 내보내기 뷰 모달
        .sheet(isPresented: $showingMultipleExportView) {
            MultipleSessionExportView(sessions: dataManager.sessionRecordings.filter { selectedSessions.contains($0.id) })
        }
    }
    
    private func deleteSessions(at offsets: IndexSet) {
        dataManager.deleteRecordings(at: offsets)
    }
}
// 새로운 세션 옵션 뷰
struct SessionOptionsView: View {
    @ObservedObject var session: SessionData
    @EnvironmentObject var dataManager: PhoneDataManager
    @Environment(\.presentationMode) var presentationMode  // 추가: presentationMode 변수
    @State private var isEditingName = false
    @State private var tempName: String
    @State private var showingDeleteAlert = false
    @State private var showingMetadataView = false
    @State private var showingExportOptions = false
    
    init(session: SessionData) {
        self._session = ObservedObject(wrappedValue: session)
        self._tempName = State(initialValue: session.name)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 세션 이름 편집
                VStack(alignment: .leading) {
                    if isEditingName {
                        TextField("세션 이름", text: $tempName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                        HStack {
                            Button("저장") {
                                session.name = tempName
                                dataManager.objectWillChange.send()
                                isEditingName = false
                            }
                            .foregroundColor(.blue)
                            Button("취소") {
                                tempName = session.name
                                isEditingName = false
                            }
                            .foregroundColor(.red)
                        }
                        .padding(.horizontal)
                    } else {
                        HStack {
                            Text(session.name)
                                .font(.title)
                            Button {
                                tempName = session.name
                                isEditingName = true
                            } label: {
                                Image(systemName: "pencil.circle")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // 세션 삭제 버튼
                Button(action: { showingDeleteAlert = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("세션 삭제")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                // 나머지 버튼들 (메타데이터, 상세정보, 시각화, 데이터 추출)
                Button(action: { showingMetadataView = true }) {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("메타데이터")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                NavigationLink(destination: SessionDetailView(session: session)) {
                    HStack {
                        Image(systemName: "list.bullet.clipboard")
                        Text("상세정보")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                NavigationLink(destination: CombinedAccelerometerVisualizationView(session: session)) {
                    HStack {
                        Image(systemName: "speedometer")
                        Text("가속도계 시각화")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                NavigationLink(destination: CombinedGyroscopeVisualizationView(session: session)) {
                    HStack {
                        Image(systemName: "gyroscope")
                        Text("자이로스코프 시각화")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                Button(action: { showingExportOptions = true }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("데이터 추출")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .padding()
        }
        .navigationTitle("세션 옵션")
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsView(session: session)
        }
        .sheet(isPresented: $showingMetadataView) {
            MetadataView()
        }
        .alert(isPresented: $showingDeleteAlert) {
            Alert(
                title: Text("세션 삭제"),
                message: Text("이 세션을 삭제하시겠습니까?"),
                primaryButton: .destructive(Text("삭제")) {
                    if let index = dataManager.sessionRecordings.firstIndex(where: { $0.id == session.id }) {
                        dataManager.deleteRecordings(at: IndexSet(integer: index))
                    }
                    presentationMode.wrappedValue.dismiss()
                },
                secondaryButton: .cancel(Text("취소"))
            )
        }
    }
}

// 메타데이터 뷰
struct MetadataView: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("기기 정보")) {
                    Text("디바이스: \(UIDevice.current.model)")
                    Text("OS 버전: \(UIDevice.current.systemVersion)")
                }
                
                Section(header: Text("센서 정보")) {
                    Text("샘플링 레이트: 100Hz")
                    Text("플랫폼: watchOS")
                }
            }
            .navigationTitle("메타데이터")
            .navigationBarItems(trailing: Button("닫기") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

// 복사 가능한 텍스트 컴포넌트
struct CopyableText: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .textSelection(.enabled)  // iOS 15 이상에서 사용 가능
        }
    }
}

// 데이터 추출 옵션 뷰
//// filepath: /Users/yoosehyeok/Documents/sensorlog_rebuild/sensorlog/ExportOptionsView.swift
import SwiftUI

import SwiftUI

struct ExportOptionsView: View {
    let session: SessionData
    @Environment(\.presentationMode) var presentationMode
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            List {
                Button(action: { prepareJSONExport() }) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("JSON 형식으로 추출")
                    }
                }
                .disabled(isProcessing)
                
                Button(action: { prepareCSVExport() }) {
                    HStack {
                        Image(systemName: "doc.plaintext")
                        Text("CSV 형식으로 추출")
                    }
                }
                .disabled(isProcessing)
                
                if isProcessing {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .navigationTitle("데이터 추출")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: shareItems)
            }
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("오류"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("확인"))
                )
            }
        }
    }
    
    // 파일 존재 확인 및 재시도 함수
    private func waitForFile(at url: URL, maxAttempts: Int = 5, completion: @escaping (Bool) -> Void) {
        var attempts = 0
        
        func check() {
            attempts += 1
            if FileManager.default.fileExists(atPath: url.path) {
                completion(true)
                return
            }
            
            if attempts >= maxAttempts {
                completion(false)
                return
            }
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                check()
            }
        }
        
        check()
    }
    
    // JSON 내보내기 함수
    private func prepareJSONExport() {
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let jsonData = try? JSONEncoder().encode(session.allSensorData) {
                let filename = "\(session.name)_sensordata.json"
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = documentsPath.appendingPathComponent(filename)
                
                do {
                    try jsonData.write(to: url)
                    
                    waitForFile(at: url) { exists in
                        DispatchQueue.main.async {
                            if exists {
                                shareItems = [url]
                                showingShareSheet = true
                            } else {
                                errorMessage = "파일 생성 시간 초과"
                                showError = true
                            }
                            isProcessing = false
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        errorMessage = "JSON 파일 생성 실패: \(error.localizedDescription)"
                        showError = true
                        isProcessing = false
                    }
                }
            }
        }
    }
    
    // CSV 내보내기 함수
    func prepareCSVExport() {
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // DOT 센서 데이터 정렬
            let dotDataSorted = session.dotSensorData.sorted { $0.startTimestamp < $1.startTimestamp }
            
            if dotDataSorted.isEmpty {
                prepareCSVExportWithoutFiltering()
                return
            }
            
            // CSV 생성 로직
            let dotStart = dotDataSorted.first!.startTimestamp
            let dotEnd = dotDataSorted.last!.startTimestamp
            let sampleInterval: TimeInterval = 1.0 / 60.0
            
            var commonTimestamps: [Date] = []
            var t = dotStart
            while t <= dotEnd {
                commonTimestamps.append(t)
                t = t.addingTimeInterval(sampleInterval)
            }
            
            let watchDataSorted = session.watchSensorData.sorted { $0.startTimestamp < $1.startTimestamp }
            var watchIndex = 0
            
            var csvString = "Timestamp,Watch_Acc_X,Watch_Acc_Y,Watch_Acc_Z,Watch_Gyro_X,Watch_Gyro_Y,Watch_Gyro_Z,DOT_Acc_X,DOT_Acc_Y,DOT_Acc_Z,DOT_Gyro_X,DOT_Gyro_Y,DOT_Gyro_Z,DOT_Euler_Roll,DOT_Euler_Pitch,DOT_Euler_Yaw,DOT_Quat_W,DOT_Quat_X,DOT_Quat_Y,DOT_Quat_Z\n"
            
            // CSV 데이터 생성
            for time in commonTimestamps {
                let formatter = DateFormatter()
                formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
                let timeStr = formatter.string(from: time)
                
                let dotEntry = dotDataSorted.min(by: {
                    abs($0.startTimestamp.timeIntervalSince(time)) < abs($1.startTimestamp.timeIntervalSince(time))
                })
                
                var watchEntry: SensorData? = nil
                if !watchDataSorted.isEmpty {
                    while watchIndex < watchDataSorted.count - 1 {
                        let currentDiff = abs(watchDataSorted[watchIndex].startTimestamp.timeIntervalSince(time))
                        let nextDiff = abs(watchDataSorted[watchIndex + 1].startTimestamp.timeIntervalSince(time))
                        if nextDiff < currentDiff {
                            watchIndex += 1
                        } else {
                            break
                        }
                    }
                    watchEntry = watchDataSorted[watchIndex]
                }
                
                var line = "\(timeStr),"
                
                if let watch = watchEntry {
                    line += "\(watch.accelerometer.x),\(watch.accelerometer.y),\(watch.accelerometer.z),"
                    line += "\(watch.gyroscope.x),\(watch.gyroscope.y),\(watch.gyroscope.z),"
                } else {
                    line += ",,,,,,"
                }
                
                if let dot = dotEntry {
                    line += "\(dot.accelerometer.x),\(dot.accelerometer.y),\(dot.accelerometer.z),"
                    line += "\(dot.gyroscope.x),\(dot.gyroscope.y),\(dot.gyroscope.z),"
                    if let euler = dot.eulerAngles {
                        line += "\(euler.roll),\(euler.pitch),\(euler.yaw),"
                    } else {
                        line += ",,,"
                    }
                    if let quaternion = dot.quaternion {
                        line += "\(quaternion.w),\(quaternion.x),\(quaternion.y),\(quaternion.z)"
                    } else {
                        line += ",,,,"
                    }
                } else {
                    line += ",,,,,,,,,,,,,"
                }
                
                csvString += line + "\n"
            }
            
            let filename = "\(session.name)_sensordata.csv"
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = documentsPath.appendingPathComponent(filename)
            
            do {
                try csvString.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    self.shareItems = [url]
                    self.showingShareSheet = true
                    self.isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "CSV 파일 생성 실패: \(error.localizedDescription)"
                    self.showError = true
                    self.isProcessing = false
                }
            }
        }
    }
    
    // DOT 센서 데이터가 없을 때의 CSV 내보내기
    private func prepareCSVExportWithoutFiltering() {
        var csvString = "Timestamp,Acc_X,Acc_Y,Acc_Z,Gyro_X,Gyro_Y,Gyro_Z,Euler_Roll,Euler_Pitch,Euler_Yaw,DOT_Acc_X,DOT_Acc_Y,DOT_Acc_Z,DOT_Gyro_X,DOT_Gyro_Y,DOT_Gyro_Z,DOT_Euler_Roll,DOT_Euler_Pitch,DOT_Euler_Yaw\n"
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        for data in session.allSensorData {
            let timestamp = formatter.string(from: data.startTimestamp)
            if data.source == "DOT" {
                csvString += "\(timestamp),,,,,,,,"  // 워치 관련 빈칸
                csvString += "\(data.accelerometer.x),\(data.accelerometer.y),\(data.accelerometer.z),"
                csvString += "\(data.gyroscope.x),\(data.gyroscope.y),\(data.gyroscope.z),"
                let dotRoll = data.eulerAngles != nil ? String(data.eulerAngles!.roll) : ""
                let dotPitch = data.eulerAngles != nil ? String(data.eulerAngles!.pitch) : ""
                let dotYaw = data.eulerAngles != nil ? String(data.eulerAngles!.yaw) : ""
                csvString += "\(dotRoll),\(dotPitch),\(dotYaw)\n"
            } else {
                csvString += "\(timestamp),"
                csvString += "\(data.accelerometer.x),\(data.accelerometer.y),\(data.accelerometer.z),"
                csvString += "\(data.gyroscope.x),\(data.gyroscope.y),\(data.gyroscope.z),"
                csvString += ",,,"   // 워치 센서 Euler 값은 빈칸
                csvString += ",,,,,,,,,\n" // DOT 관련 컬럼 빈칸
            }
        }
        
        let filename = "\(session.name)_sensordata.csv"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documentsPath.appendingPathComponent(filename)
        
        do {
            try csvString.write(to: url, atomically: true, encoding: .utf8)
            
            waitForFile(at: url) { exists in
                DispatchQueue.main.async {
                    if exists {
                        shareItems = [url]
                        showingShareSheet = true
                    } else {
                        errorMessage = "파일 생성 시간 초과"
                        showError = true
                    }
                    isProcessing = false
                }
            }
        } catch {
            DispatchQueue.main.async {
                errorMessage = "CSV 파일 생성 실패: \(error.localizedDescription)"
                showError = true
                isProcessing = false
            }
        }
    }
}

// ShareSheet 구현
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
// ShareSheet를 위한 UIViewControllerRepresentable

struct cRecordingDetailView: View {
    let recording: SensorData
    @Binding var selectedRecording: SensorData?
    
    var formattedTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: recording.startTimestamp)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recording Details")
                .font(.largeTitle)
                .bold()
            Text("Start Time: \(recording.startTimestamp)")
            if let stopTime = recording.stopTimestamp {
                Text("End Time: \(stopTime)")
            } else {
                Text("End Time: Ongoing")
            }

            // 가속도계 데이터 표시
            Text("Accelerometer Data:")
            Text("x: \(recording.accelerometer.x), y: \(recording.accelerometer.y), z: \(recording.accelerometer.z)")

            // 자이로스코프 데이터 표시
            Text("Gyroscope Data:")
            Text("x: \(recording.gyroscope.x), y: \(recording.gyroscope.y), z: \(recording.gyroscope.z)")

            Spacer()
        }
        .padding()
        .navigationTitle(formattedTitle)
    }
}

// 다중 세션 내보내기 뷰
struct MultipleSessionExportView: View {
    let sessions: [SessionData]
    @Environment(\.presentationMode) var presentationMode
    @State private var showingShareSheet = false
    @State private var shareURLs: [URL] = []
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            List {
                Button(action: { exportAsJSON() }) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("JSON 형식으로 추출")
                    }
                }
                .disabled(isProcessing)
                
                Button(action: { exportAsCSV() }) {
                    HStack {
                        Image(systemName: "doc.plaintext")
                        Text("CSV 형식으로 추출")
                    }
                }
                .disabled(isProcessing)
                
                if isProcessing {
                    ProgressView()
                }
            }
            .navigationTitle("데이터 추출")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: shareURLs)
            }
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("오류"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("확인"))
                )
            }
        }
    }
    
    func exportAsJSON() {
        shareURLs.removeAll()
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            for session in sessions {
                let exportData: [String: Any] = [
                    "sessionName": session.name,
                    "startTime": session.startTimestamp,
                    "stopTime": session.stopTimestamp as Any,
                    "sensorData": session.allSensorData
                ]
                
                if let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted),
                   let fileURL = createTempFile(data: jsonData, filename: "\(session.name)_data", ext: "json") {
                    DispatchQueue.main.async {
                        self.shareURLs.append(fileURL)
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.showingShareSheet = true
            }
        }
    }
    
    func exportAsCSV() {
        shareURLs.removeAll()
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            for session in sessions {
                let dotDataSorted = session.dotSensorData.sorted { $0.startTimestamp < $1.startTimestamp }
                
                if dotDataSorted.isEmpty {
                    continue
                }
                
                let dotStart = dotDataSorted.first!.startTimestamp
                let dotEnd = dotDataSorted.last!.startTimestamp
                let sampleInterval: TimeInterval = 1.0 / 60.0
                
                var commonTimestamps: [Date] = []
                var t = dotStart
                while t <= dotEnd {
                    commonTimestamps.append(t)
                    t = t.addingTimeInterval(sampleInterval)
                }
                
                let watchDataSorted = session.watchSensorData.sorted { $0.startTimestamp < $1.startTimestamp }
                var watchIndex = 0
                
                var csvString = "Timestamp,Watch_Acc_X,Watch_Acc_Y,Watch_Acc_Z,Watch_Gyro_X,Watch_Gyro_Y,Watch_Gyro_Z,DOT_Acc_X,DOT_Acc_Y,DOT_Acc_Z,DOT_Gyro_X,DOT_Gyro_Y,DOT_Gyro_Z,DOT_Euler_Roll,DOT_Euler_Pitch,DOT_Euler_Yaw,DOT_Quat_W,DOT_Quat_X,DOT_Quat_Y,DOT_Quat_Z\n"

                for time in commonTimestamps {
                    let formatter = DateFormatter()
                    formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
                    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
                    let timeStr = formatter.string(from: time)
                    
                    let dotEntry = dotDataSorted.min(by: {
                        abs($0.startTimestamp.timeIntervalSince(time)) < abs($1.startTimestamp.timeIntervalSince(time))
                    })
                    
                    var watchEntry: SensorData? = nil
                    if !watchDataSorted.isEmpty {
                        while watchIndex < watchDataSorted.count - 1 {
                            let currentDiff = abs(watchDataSorted[watchIndex].startTimestamp.timeIntervalSince(time))
                            let nextDiff = abs(watchDataSorted[watchIndex + 1].startTimestamp.timeIntervalSince(time))
                            if nextDiff < currentDiff {
                                watchIndex += 1
                            } else {
                                break
                            }
                        }
                        watchEntry = watchDataSorted[watchIndex]
                    }
                    
                    var line = "\(timeStr),"
                    
                    if let watch = watchEntry {
                        line += "\(watch.accelerometer.x),\(watch.accelerometer.y),\(watch.accelerometer.z),"
                        line += "\(watch.gyroscope.x),\(watch.gyroscope.y),\(watch.gyroscope.z),"
                    } else {
                        line += ",,,,,,"
                    }
                    
                    if let dot = dotEntry {
                        line += "\(dot.accelerometer.x),\(dot.accelerometer.y),\(dot.accelerometer.z),"
                        line += "\(dot.gyroscope.x),\(dot.gyroscope.y),\(dot.gyroscope.z),"
                        if let euler = dot.eulerAngles {
                            line += "\(euler.roll),\(euler.pitch),\(euler.yaw),"
                        } else {
                            line += ",,,"
                        }
                        if let quaternion = dot.quaternion {
                            line += "\(quaternion.w),\(quaternion.x),\(quaternion.y),\(quaternion.z)"
                        } else {
                            line += ",,,,"
                        }
                    } else {
                        line += ",,,,,,,,,,,,,"
                    }
                    
                    csvString += line + "\n"
                }
                
                let filename = "\(session.name).csv"
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = documentsPath.appendingPathComponent(filename)
                
                do {
                    try csvString.write(to: url, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.shareURLs.append(url)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "CSV 파일 생성 실패: \(error.localizedDescription)"
                        self.showError = true
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.showingShareSheet = true
            }
        }
    }
    
    func createTempFile(data: Data, filename: String, ext: String) -> URL? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent("\(filename).\(ext)")
        do {
            try data.write(to: fileURL, options: [.atomic])
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            } else {
                return nil
            }
        } catch {
            print("파일 생성 실패:", error.localizedDescription)
            return nil
        }
    }

    
    /// 지정된 URL의 파일들이 모두 존재하는지 확인하는 함수
    func waitForFilesToExist(urls: [URL], retries: Int, delay: TimeInterval, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            let allExist = urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
            if allExist || retries <= 0 {
                completion(allExist)
            } else {
                waitForFilesToExist(urls: urls, retries: retries - 1, delay: delay, completion: completion)
            }
        }
    }
}
