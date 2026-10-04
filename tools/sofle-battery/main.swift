// Shows both Sofle halves' battery levels in the macOS menu bar.
//
// ZMK's central (left) exposes a Battery Service for itself and, thanks to
// CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY, a second one holding each
// split peripheral's (right) level. macOS only shows the first one, so this
// app reads them all directly.
//
// Usage:
//   SofleBattery          menu bar app
//   SofleBattery --once   print levels and exit (for the terminal)

import AppKit
import CoreBluetooth

let keyboardName = "Sofle"
let batteryService = CBUUID(string: "180F")
let batteryLevel = CBUUID(string: "2A19")
let refreshInterval: TimeInterval = 300
let lowBattery = 20

final class BatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristics: [CBCharacteristic] = []
    private(set) var levels: [Int?] = []
    private(set) var status = "Searching…"
    var onUpdate: (() -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func refresh() {
        guard central.state == .poweredOn else { return }
        if let peripheral, peripheral.state == .connected, !characteristics.isEmpty {
            characteristics.forEach { peripheral.readValue(for: $0) }
        } else {
            findKeyboard()
        }
    }

    private func findKeyboard() {
        let connected = central.retrieveConnectedPeripherals(withServices: [batteryService])
        guard let keyboard = connected.first(where: { ($0.name ?? "").contains(keyboardName) }) else {
            peripheral = nil
            characteristics = []
            levels = []
            update("Keyboard not connected")
            return
        }
        peripheral = keyboard
        keyboard.delegate = self
        central.connect(keyboard)
    }

    private func update(_ newStatus: String) {
        status = newStatus
        onUpdate?()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: findKeyboard()
        case .unauthorized: update("Bluetooth permission denied")
        case .poweredOff: update("Bluetooth is off")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        update("Could not connect")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        characteristics = []
        levels = []
        update("Keyboard not connected")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = (peripheral.services ?? []).filter { $0.uuid == batteryService }
        guard !services.isEmpty else {
            update("No battery service")
            return
        }
        services.forEach { peripheral.discoverCharacteristics([batteryLevel], for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let services = (peripheral.services ?? []).filter { $0.uuid == batteryService }
        guard services.allSatisfy({ $0.characteristics != nil }) else { return }

        // The central's own service comes first, then the peripherals' one.
        characteristics = services.flatMap { ($0.characteristics ?? []).filter { $0.uuid == batteryLevel } }
        levels = Array(repeating: nil, count: characteristics.count)
        for characteristic in characteristics {
            peripheral.readValue(for: characteristic)
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let index = characteristics.firstIndex(where: { $0 === characteristic }),
              let byte = characteristic.value?.first else { return }
        levels[index] = Int(byte)
        update("Connected")
    }
}

func halfName(_ index: Int) -> String {
    index == 0 ? "Left" : index == 1 ? "Right" : "Half \(index + 1)"
}

func formatLevel(_ level: Int?) -> String {
    level.map { "\($0)%" } ?? "…"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let reader = BatteryReader()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        reader.onUpdate = { [weak self] in self?.render() }
        render()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.reader.refresh()
        }
    }

    private func render() {
        let levels = reader.levels
        let title: String
        let low = levels.contains { ($0 ?? 100) <= lowBattery }
        if levels.isEmpty {
            title = "–"
        } else {
            title = levels.enumerated().map { index, level in
                "\(halfName(index).prefix(1)) \(formatLevel(level))"
            }.joined(separator: "  ")
        }
        let symbol = low ? "exclamationmark.triangle" : "keyboard"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Sofle battery")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = " " + title

        let menu = NSMenu()
        if levels.isEmpty {
            menu.addItem(withTitle: reader.status, action: nil, keyEquivalent: "")
        } else {
            for (index, level) in levels.enumerated() {
                menu.addItem(withTitle: "\(halfName(index)): \(formatLevel(level))", action: nil, keyEquivalent: "")
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func refresh() {
        reader.refresh()
    }
}

if CommandLine.arguments.contains("--once") {
    let reader = BatteryReader()
    reader.onUpdate = {
        let levels = reader.levels
        if levels.isEmpty {
            if reader.status != "Searching…" {
                print(reader.status)
                exit(1)
            }
        } else if levels.allSatisfy({ $0 != nil }) {
            print(levels.enumerated().map { "\(halfName($0)): \(formatLevel($1))" }.joined(separator: "  "))
            exit(0)
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
        print("Timed out: \(reader.status)")
        exit(1)
    }
    RunLoop.main.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
