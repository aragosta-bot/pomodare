import Foundation
import CoreGraphics
import AppKit

/// Tracks user activity using CGEventTap and idle detection.
/// Requires Accessibility permission (AXIsProcessTrusted).
final class ActivityTracker {
    var onIdleChanged: ((Bool) -> Void)?

    private(set) var activeSeconds: Int = 0
    private var isRunning = false
    private var isIdle = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tickTimer: Timer?
    private var idleCheckTimer: Timer?

    // Idle threshold: 120 seconds
    private let idleThreshold: TimeInterval = 120

    func start() {
        guard !isRunning else { return }

        // Check accessibility permission
        if !AXIsProcessTrusted() {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options)
            // We'll try to tap anyway — may fail silently
        }

        setupEventTap()
        startTimers()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        teardownEventTap()
        tickTimer?.invalidate()
        tickTimer = nil
        idleCheckTimer?.invalidate()
        idleCheckTimer = nil
    }

    // MARK: - Event Tap

    private func setupEventTap() {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, _, userInfo in
                if let ptr = userInfo {
                    let tracker = Unmanaged<ActivityTracker>.fromOpaque(ptr).takeUnretainedValue()
                    tracker.onEventReceived()
                }
                return nil
            },
            userInfo: selfPtr
        ) else {
            print("Pomodare: CGEvent tap failed (no Accessibility permission?)")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func teardownEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    @objc private func onEventReceived() {
        // Called from main thread via run loop
        if isIdle {
            setIdle(false)
        }
    }

    // MARK: - Timers

    private func startTimers() {
        // Tick every second to increment active time
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning, !self.isIdle else { return }
            self.activeSeconds += 1
        }

        // Check idle every 5 seconds
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
    }

    private func checkIdle() {
        let idleTime = secondsSinceLastEvent()
        let shouldBeIdle = idleTime >= idleThreshold
        if shouldBeIdle != isIdle {
            setIdle(shouldBeIdle)
        }
    }

    private func setIdle(_ idle: Bool) {
        isIdle = idle
        onIdleChanged?(idle)
    }

    // MARK: - Idle Time Detection

    /// Returns seconds since the last user input event (keyboard or mouse).
    private func secondsSinceLastEvent() -> TimeInterval {
        // Try CGEventSource first (more accurate)
        let keyboardIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .keyDown
        )
        let mouseIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .mouseMoved
        )
        let clickIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .leftMouseDown
        )
        return min(keyboardIdle, min(mouseIdle, clickIdle))
    }
}
