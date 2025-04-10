import SwiftUI
import Charts

struct RealtimeGraphView: View {
    @EnvironmentObject var dataManager: PhoneDataManager
    @State private var quaternionData: [(timestamp: Date, w: Double, x: Double, y: Double, z: Double)] = []
    @State private var lastUpdateTime = Date()
    @State private var currentAngles: (roll: Double, pitch: Double, yaw: Double) = (0, 0, 0)
    @State private var lastReceiveTime = Date()
    @State private var connectionStatus = "연결됨"
    
    let xColor = Color.red
    let yColor = Color.green
    let zColor = Color.blue
    
    // 타이머 간격 수정
    let angleUpdateTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect() // 1초에서 0.5초로 감소
    let connectionCheckTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect() // 0.5초에서 0.2초로 감소
 
    var body: some View {
        VStack {
            HStack {
                Text("실시간 각도 데이터")
                    .font(.headline)
                Spacer()
                Text(connectionStatus)
                    .font(.subheadline)
                    .foregroundColor(connectionStatus == "연결됨" ? .green : .red)
            }
            .padding(.horizontal)
            
            // 각도 시각화 및 표시 추가
            VStack(spacing: 15) {
                // 3D 회전 시각화
                HStack(spacing: 25) {
                    // Roll (X축) 시각화
                    VStack {
                        Text("Roll (X)")
                            .font(.subheadline)
                            .foregroundColor(xColor)
                        
                        ZStack {
                            // 기준선
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 80, height: 2)
                            
                            // 회전하는 선
                            Rectangle()
                                .fill(xColor)
                                .frame(width: 80, height: 4)
                                .rotationEffect(.degrees(currentAngles.roll), anchor: .center)
                        }
                        .frame(width: 80, height: 80)
                        .background(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        
                        Text(String(format: "%.1f°", currentAngles.roll))
                            .font(.title3)
                            .foregroundColor(xColor)
                    }
                    
                    // Pitch (Y축) 시각화
                    VStack {
                        Text("Pitch (Y)")
                            .font(.subheadline)
                            .foregroundColor(yColor)
                        
                        ZStack {
                            // 기준선
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 2, height: 80)
                            
                            // 회전하는 선
                            Rectangle()
                                .fill(yColor)
                                .frame(width: 4, height: 80)
                                .rotationEffect(.degrees(currentAngles.pitch), anchor: .center)
                        }
                        .frame(width: 80, height: 80)
                        .background(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        
                        Text(String(format: "%.1f°", currentAngles.pitch))
                            .font(.title3)
                            .foregroundColor(yColor)
                    }
                    
                    // Yaw (Z축) 시각화
                    VStack {
                        Text("Yaw (Z)")
                            .font(.subheadline)
                            .foregroundColor(zColor)
                        
                        ZStack {
                            // 나침반 같은 표시
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                .frame(width: 80, height: 80)
                            
                            // 북쪽 표시
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 2, height: 40)
                                .offset(y: -20)
                            
                            // 방향 화살표
                            VStack {
                                Image(systemName: "arrowtriangle.up.fill")
                                    .foregroundColor(zColor)
                                Spacer()
                            }
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(currentAngles.yaw), anchor: .center)
                        }
                        .frame(width: 80, height: 80)
                        
                        Text(String(format: "%.1f°", currentAngles.yaw))
                            .font(.title3)
                            .foregroundColor(zColor)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(15)
            }
            .padding(.horizontal)
            
            // 쿼터니언 값 표시 (W 제외)
            HStack(spacing: 15) {
                QuaternionValueView(label: "X", value: quaternionData.last?.x ?? 0, color: xColor)
                QuaternionValueView(label: "Y", value: quaternionData.last?.y ?? 0, color: yColor)
                QuaternionValueView(label: "Z", value: quaternionData.last?.z ?? 0, color: zColor)
            }
            .padding(.vertical, 10)
            
            // 그래프 (W 제외)
            Chart {
                // X 값
                ForEach(quaternionData.indices, id: \.self) { index in
                    let data = quaternionData[index]
                    LineMark(
                        x: .value("Time", data.timestamp),
                        y: .value("Value", data.x)
                    )
                    .foregroundStyle(xColor)
                    .interpolationMethod(.catmullRom)
                }
                
                // Y 값
                ForEach(quaternionData.indices, id: \.self) { index in
                    let data = quaternionData[index]
                    LineMark(
                        x: .value("Time", data.timestamp),
                        y: .value("Value", data.y)
                    )
                    .foregroundStyle(yColor)
                    .interpolationMethod(.catmullRom)
                }
                
                // Z 값
                ForEach(quaternionData.indices, id: \.self) { index in
                    let data = quaternionData[index]
                    LineMark(
                        x: .value("Time", data.timestamp),
                        y: .value("Value", data.z)
                    )
                    .foregroundStyle(zColor)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: -1.0...1.0)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                }
            }
            .frame(height: 200)
            .padding(.horizontal)
            
            // 범례 (W 제외)
            HStack(spacing: 20) {
                QuaternionLegendItem(color: xColor, label: "X")
                QuaternionLegendItem(color: yColor, label: "Y")
                QuaternionLegendItem(color: zColor, label: "Z")
            }
            .padding(.bottom, 5)
            
            Spacer()
        }
        // 데이터 수신 및 처리
        .onReceive(connectionCheckTimer) { _ in
            updateData()
        }
        // 연결 상태만 확인 (각도는 updateData에서 업데이트)
        .onReceive(angleUpdateTimer) { _ in
            checkConnection()
        }
        .onDisappear {
            // 화면이 사라질 때 타이머 중지
            angleUpdateTimer.upstream.connect().cancel()
            connectionCheckTimer.upstream.connect().cancel()
        }
    }
    
    // 데이터 수신 함수
    private func updateData() {
        guard let latestCSVString = dataManager.latestWatchCSV else { return }
        
        // CSV 형식: "timestamp,accX,accY,accZ,gyroX,gyroY,gyroZ,quatW,quatX,quatY,quatZ\n"
        let components = latestCSVString.split(separator: ",")
        
        // 7번째(w), 8번째(x), 9번째(y), 10번째(z) 인덱스가 쿼터니언 데이터
        guard components.count >= 11, 
            let w = Double(components[7]),
            let x = Double(components[8]), 
            let y = Double(components[9]), 
            let z = Double(components[10].trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        
        let now = Date()
        
        // 최신 데이터 저장 (데이터가 변경되었는지 여부에 관계없이)
        let currentData = (timestamp: now, w: w, x: x, y: y, z: z)
        
        // 새 데이터가 도착했으면 마지막 수신 시간 업데이트
        let isNewData = quaternionData.isEmpty || 
                        (w != quaternionData.last!.w || x != quaternionData.last!.x || 
                        y != quaternionData.last!.y || z != quaternionData.last!.z)
        
        if isNewData {
            lastReceiveTime = now
            connectionStatus = "연결됨"
            
            // 쿼터니언을 오일러 각도로 즉시 변환하여 업데이트
            let angles = quaternionToEulerAngles(w: w, x: x, y: y, z: z)
            withAnimation(.easeInOut(duration: 0.3)) {
                currentAngles = angles
            }
        }
        
        // 데이터 추가 (제한 없음) - 항상 최신 데이터를 추가합니다
        quaternionData.append(currentData)
    
    }
    
    // 각도 계산 함수 (1초마다 호출)
    private func updateAngle() {
        // 이제 updateData()에서 데이터를 받을 때마다 즉시 각도를 계산하므로
        // 이 함수는 연결 확인 목적으로만 사용
        checkConnection()
    }
    
    // 연결 상태 확인 함수
    private func checkConnection() {
        let now = Date()
        // 2초 이상 새 데이터가 없으면 연결 끊김으로 간주 (3초에서 2초로 감소)
        if now.timeIntervalSince(lastReceiveTime) > 2.0 {
            connectionStatus = "연결 끊김"
        }
    }
    
    // 쿼터니언을 오일러 각도(라디안)로 변환하는 함수 (기존과 동일)
    private func quaternionToEulerAngles(w: Double, x: Double, y: Double, z: Double) -> (roll: Double, pitch: Double, yaw: Double) {
        // 회전 행렬 요소 계산
        let sqw = w * w
        let sqx = x * x
        let sqy = y * y
        let sqz = z * z
        
        // 롤 (x-축 회전) - 오른손 좌표계 기준
        let roll = atan2(2.0 * (w * x + y * z), sqw - sqx - sqy + sqz)
        
        // 피치 (y-축 회전)
        // singularity 처리 (gimbal lock 방지)
        var pitch: Double
        let sinp = 2.0 * (w * y - z * x)
        if abs(sinp) >= 1 {
            pitch = sinp > 0 ? .pi / 2 : -.pi / 2 // 90도 또는 -90도
        } else {
            pitch = asin(sinp)
        }
        
        // 요 (z-축 회전)
        let yaw = atan2(2.0 * (w * z + x * y), sqw + sqx - sqy - sqz)
        
        // 라디안에서 각도로 변환
        let rollDeg = roll * (180.0 / .pi)
        let pitchDeg = pitch * (180.0 / .pi)
        let yawDeg = yaw * (180.0 / .pi)
        
        return (rollDeg, pitchDeg, yawDeg)
    }
}


// 각도 표시용 뷰
struct AngleView: View {
    let label: String
    let angle: Double
    let color: Color
    
    var body: some View {
        VStack {
            Text(label)
                .font(.headline)
                .foregroundColor(color)
            Text(String(format: "%.1f°", angle))
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(minWidth: 70)
        .padding(8)
    }
}

// 값 표시용 뷰
struct QuaternionValueView: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack {
            Text(label)
                .font(.headline)
                .foregroundColor(color)
            Text(String(format: "%.4f", value))
                .font(.body)
        }
        .frame(minWidth: 60)
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// 범례 아이템
struct QuaternionLegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(color)
                .frame(width: 15, height: 3)
            Text(label)
                .font(.caption)
        }
    }
}