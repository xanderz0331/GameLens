import AppKit
import Carbon.HIToolbox

private var gHotKeyTrigger: ((UInt32) -> Void)?

private func gameLensHotKeyHandler(_ nextHandler: EventHandlerCallRef?,
                                   _ event: EventRef?,
                                   _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    if status == noErr { gHotKeyTrigger?(hotKeyID.id) }
    return noErr
}

/// 全局热键（Carbon RegisterEventHotKey，不需要辅助功能权限，不会打断游戏输入）
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var currentPreset: HotKeyPreset?
    var onTrigger: (() -> Void)?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),
                            gameLensHotKeyHandler,
                            1,
                            &spec,
                            nil,
                            &eventHandler)
        gHotKeyTrigger = { [weak self] _ in self?.onTrigger?() }
    }

    deinit {
        unregister()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    @discardableResult
    func register(_ preset: HotKeyPreset) -> Bool {
        if currentPreset == preset, hotKeyRef != nil { return true }
        unregister()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x474C4E53), id: 1) // 'GLNS'
        let status = RegisterEventHotKey(UInt32(preset.keyCode),
                                         UInt32(preset.carbonModifiers),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        currentPreset = preset
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        currentPreset = nil
    }
}
