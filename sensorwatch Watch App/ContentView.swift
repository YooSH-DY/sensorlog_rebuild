import SwiftUI

struct watchContentView: View {
    @StateObject private var sensorManager = WatchSensorManager()

    var body: some View {
        VStack {
            Text(sensorManager.isRecording ? "Recording..." : "Ready")
                .font(.headline)

            Button(action: {
                if sensorManager.isRecording {
                    sensorManager.stopRecording()
                } else {
                    sensorManager.startRecording()
                }
            }) {
                Text(sensorManager.isRecording ? "Stop Recording" : "Start Recording")
                    .foregroundColor(.white)
                    .padding()
                    .background(sensorManager.isRecording ? Color.red : Color.green)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}
