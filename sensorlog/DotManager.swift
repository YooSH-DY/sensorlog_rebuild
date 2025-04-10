// DotManager.swift
import Foundation
import MovellaDotSdk
import CoreBluetooth


class DotManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var connectedDots: [DotDevice] = []
    @Published var discoveredDots: [DotDevice] = []
    @Published var batteryLevels: [String: Int] = [:]
    
    // 싱글턴 인스턴스로 관리
    static let shared = DotManager()
    
    override init() {
        super.init()
        configureConnectionDelegate()
        enableReconnectManager()
        startBatteryPollingTimer()  // 타이머 시작
    }
    /// 3분마다 연결된 센서들의 배터리 정보를 읽어 batteryLevels를 업데이트하는 타이머
    private func startBatteryPollingTimer() {
        Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                for device in self.connectedDots {
                    if let battery = device.battery {
                        self.batteryLevels[device.uuid] = battery.value
                        print("Periodic update for \(device.uuid): \(battery.value)%")
                    } else {
                        print("Periodic update for \(device.uuid): no battery info available")
                    }
                }
            }
        }
    }
    
    private func configureConnectionDelegate() {
        DotConnectionManager.setConnectionDelegate(self)
    }
    
    private func enableReconnectManager() {
        DotReconnectManager.setEnable(true)
    }
    
    @MainActor
    func startScan(clearDiscovered: Bool = true) {
        isScanning = true
        if clearDiscovered {
            discoveredDots.removeAll()
        } else {
            // 연결된 센서만 남기도록 재필터링 (선택 사항)
            discoveredDots = discoveredDots.filter { device in
                connectedDots.contains(where: { $0.uuid == device.uuid })
            }
            
        }
        DotConnectionManager.scan()
    }
    
    @MainActor
    func stopScan() {
        isScanning = false
        DotConnectionManager.stopScan()
    }
    
        func connect(to device: DotDevice) {
        // 블루투스 트래픽 분산
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            DotConnectionManager.connect(device)
            DotDevicePool.bindDevice(device)
        }
    }
    // 연결 우선순위 로직 추가
    func connectWithPriority(devices: [DotDevice]) {
        // 기기별 연결 간격을 두어 블루투스 충돌 방지
        for (index, device) in devices.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 1.0) {
                self.connect(to: device)
            }
        }
    }
    
    func disconnect(device: DotDevice) {
        DotConnectionManager.disconnect(device)
        DotDevicePool.unbindDevice(device)
    }
    
    @MainActor
    func refreshScan() async {
        // 연결된 센서만 남기고 나머지 제거하여 유지
        self.discoveredDots = self.discoveredDots.filter { device in
            self.connectedDots.contains(where: { $0.uuid == device.uuid })
        }
        
        // 현재 스캔 중이면 중지
        stopScan()
        
        // 잠시 대기 후 스캔 재시작 (clearDiscovered: false로 연결된 센서는 유지)
        try? await Task.sleep(nanoseconds: 500_000_000)
        startScan(clearDiscovered: false)
        
        // 추가 스캔 결과를 받아들일 시간을 줌
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
    
    @objc func batteryDidUpdate(_ notification: Notification) {
        guard let device = notification.object as? DotDevice else {
            print("Invalid device in battery update notification.")
            return
        }

        if let batteryLevel = notification.userInfo?["batterylevel"] as? Int {
            DispatchQueue.main.async {
                self.batteryLevels[device.uuid] = batteryLevel
                print("Battery level for \(device.uuid): \(batteryLevel)%")
            }
        } else {
            print("Failed to parse battery level for device \(device.uuid).")
        }
    }

    @objc func deviceInitialized(_ notification: Notification) {
        guard let device = notification.object as? DotDevice else { return }
        print("Device \(device.uuid) has been initialized.")

        // 배터리 업데이트 알림 재등록
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.batteryDidUpdate(_:)),
            name: NSNotification.Name("kDotNotificationDeviceBatteryDidUpdate"),
            object: device
        )
    }
    
}

extension DotManager: DotConnectionDelegate {
    func onDiscover(_ device: DotDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.discoveredDots.contains(where: { $0.uuid == device.uuid }) {
                self.discoveredDots.append(device)
            }
        }
    }

    func onDeviceConnectSucceeded(_ device: DotDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 연결된 센서를 목록에 추가
            if !self.connectedDots.contains(where: { $0.uuid == device.uuid }) {
                self.connectedDots.append(device)
            }
            
            // 2초 후에 실제 배터리 정보를 읽어와서 갱신
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let battery = device.battery {
                    self.batteryLevels[device.uuid] = battery.value
                    print("Device \(device.uuid): 2초 후 배터리 업데이트 \(battery.value)%")
                } else {
                    print("Device \(device.uuid): 2초 후에도 배터리 정보 없음")
                }
            }
            
            // 센서 초기화 여부에 따라 초기화 알림 등록 (초기화 상태면 바로 넘어감)
            if !device.isInitialized() {
                print("Device \(device.uuid) is not initialized yet. Forcing initialization.")
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(self.deviceInitialized(_:)),
                    name: NSNotification.Name("kDotNotificationDeviceInitialized"),
                    object: device)
            } else {
                print("Device \(device.uuid) is already initialized.")
            }
            
            // 배터리 업데이트 알림은 항상 등록 (향후 정보 업데이트를 위해)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.batteryDidUpdate(_:)),
                name: NSNotification.Name("kDotNotificationDeviceBatteryDidUpdate"),
                object: device)
        }
    }




    func onDeviceConnectFailed(_ device: DotDevice) {
        print("센서 연결 실패: \(device.uuid)")
    }

    func onDeviceDisconnected(_ device: DotDevice) {
        DispatchQueue.main.async { [weak self] in
            self?.connectedDots.removeAll(where: { $0.uuid == device.uuid })
        }
    }
}
