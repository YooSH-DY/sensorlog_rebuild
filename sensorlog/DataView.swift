import SwiftUI

struct DataView: View {
    let recording: SensorData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recording Data")
                    .font(.largeTitle)
                    .bold()

                if let jsonString = try? String(data: JSONEncoder().encode(recording), encoding: .utf8) {
                    Text(jsonString)
                        .font(.body)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    Text("Failed to encode data.")
                        .foregroundColor(.red)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Data Viewer")
    }
}
