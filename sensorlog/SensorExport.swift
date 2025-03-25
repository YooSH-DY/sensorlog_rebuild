import SwiftUI
import Foundation
struct SensorExportOptionsView: View {
    // SensorData는 이미 정의되어 있다고 가정합니다.
    let sensorDatas: [SensorData]
    @Environment(\.presentationMode) var presentationMode
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("센서 데이터 내보내기")
                    .font(.largeTitle)
                    .bold()
                
                Button("CSV로 내보내기") {
                    exportAsCSV()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            .navigationBarItems(trailing: Button("닫기") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: shareItems)
        }
    }
    
    func exportAsCSV() {
        // CSV 헤더 작성: 필요에 따라 필드를 수정하세요.
        var csvString = "ID,StartTimestamp,StopTimestamp,Acc_X,Acc_Y,Acc_Z,Gyro_X,Gyro_Y,Gyro_Z,Roll,Pitch,Yaw\n"
        for data in sensorDatas {
            let idString = data.id.uuidString
            let start = data.startTimestamp.timeIntervalSince1970
            let stop = data.stopTimestamp?.timeIntervalSince1970 ?? 0
            let accX = data.accelerometer.x
            let accY = data.accelerometer.y
            let accZ = data.accelerometer.z
            let gyroX = data.gyroscope.x
            let gyroY = data.gyroscope.y
            let gyroZ = data.gyroscope.z
            // eulerAngles가 옵셔널로 정의되어 있다면 적절한 기본값(여기서는 0)을 사용합니다.
            let roll = data.eulerAngles?.roll ?? 0
            let pitch = data.eulerAngles?.pitch ?? 0
            let yaw = data.eulerAngles?.yaw ?? 0
            
            let line = "\(idString),\(start),\(stop),\(accX),\(accY),\(accZ),\(gyroX),\(gyroY),\(gyroZ),\(roll),\(pitch),\(yaw)\n"
            csvString.append(line)
        }
        
        // 임시 파일 경로에 CSV 내용을 저장합니다.
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("SensorDataExport.csv")
        
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            shareItems = [fileURL]
            showingShareSheet = true
        } catch {
            print("CSV 파일 생성 실패: \(error)")
        }
    }
    


}

struct SensorExportOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        // 미리보기용 빈 배열. 실제 사용시 sensorDatas 배열을 전달합니다.
        SensorExportOptionsView(sensorDatas: [])
    }
}
