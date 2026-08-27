import Carbon
import Foundation

final class GlobalShortcutManager {
    enum Action: Int {
        case startRecording = 1
        case pauseResume = 2
        case stopRecording = 3
        case toggleCamera = 4
        case toggleMicrophone = 5

        var displayShortcut: String {
            switch self {
            case .startRecording:
                return "⌘ ⇧ R"
            case .pauseResume:
                return "⌘ ⇧ P"
            case .stopRecording:
                return "⌘ ⇧ S"
            case .toggleCamera:
                return "⌘ ⇧ C"
            case .toggleMicrophone:
                return "⌘ ⇧ M"
            }
        }
    }

    var onAction: ((Action) -> Void)?
    var onRegistrationIssue: ((String) -> Void)?

    private static weak var activeManager: GlobalShortcutManager?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [Action: EventHotKeyRef] = [:]

    init() {
        Self.activeManager = self
    }

    deinit {
        unregisterAll()
    }

    func registerDefaults() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )

        guard status == noErr else {
            FramecastLogger.capture.error("Failed installing global hotkey handler: \(status)")
            return
        }

        register(action: .startRecording, keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey))
        register(action: .pauseResume, keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | shiftKey))
        register(action: .stopRecording, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey))
        register(action: .toggleCamera, keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey))
        register(action: .toggleMicrophone, keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | shiftKey))
    }

    func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    private func register(action: Action, keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x46524354), id: UInt32(action.rawValue))
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)

        guard status == noErr, let hotKeyRef else {
            FramecastLogger.capture.error("Failed registering hotkey for action \(action.rawValue): \(status)")
            if status == eventHotKeyExistsErr {
                onRegistrationIssue?("Shortcut conflict for \(action.displayShortcut)")
            } else {
                onRegistrationIssue?("Could not register \(action.displayShortcut)")
            }
            return
        }

        hotKeyRefs[action] = hotKeyRef
    }

    fileprivate static func dispatchHotKey(id: UInt32) {
        guard let manager = activeManager,
              let action = Action(rawValue: Int(id)) else {
            return
        }

        DispatchQueue.main.async {
            manager.onAction?(action)
        }
    }
}

private let globalHotKeyHandler: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else {
        return OSStatus(eventNotHandledErr)
    }

    GlobalShortcutManager.dispatchHotKey(id: hotKeyID.id)
    return noErr
}
