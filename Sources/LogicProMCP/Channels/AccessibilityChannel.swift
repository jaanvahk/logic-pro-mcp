import AppKit
import ApplicationServices
import Foundation

/// Channel that reads and mutates Logic Pro state via the macOS Accessibility API.
/// Primary channel for state queries (transport, tracks, mixer) and UI mutations
/// (clicking mute/solo buttons, reading fader values, etc.)
actor AccessibilityChannel: Channel {
    let id: ChannelID = .accessibility

    func start() async throws {
        // Verify AX trust. If not trusted, the process needs to be added to
        // System Preferences > Privacy & Security > Accessibility.
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            throw AccessibilityError.notTrusted
        }
        guard ProcessUtils.isLogicProRunning else {
            Log.warn("Logic Pro not running at AX channel start", subsystem: "ax")
            return
        }
        Log.info("Accessibility channel started", subsystem: "ax")
    }

    func stop() async {
        Log.info("Accessibility channel stopped", subsystem: "ax")
    }

    func execute(operation: String, params: [String: String]) async -> ChannelResult {
        guard ProcessUtils.isLogicProRunning else {
            return .error("Logic Pro is not running")
        }

        switch operation {
        // MARK: - Transport reads
        case "transport.get_state":
            return getTransportState()

        // MARK: - Transport mutations
        case "transport.toggle_cycle":
            return toggleTransportButton(named: "Cycle")
        case "transport.toggle_metronome":
            return toggleTransportButton(named: "Metronome")
        case "transport.set_tempo":
            return setTempo(params: params)
        case "transport.set_cycle_range":
            return setCycleRange(params: params)

        // MARK: - Track reads
        case "track.get_tracks":
            return getTracks()
        case "track.count":
            let count = AXLogicProElements.allTrackHeaders().filter { AXHelpers.getRole($0) == kAXLayoutItemRole }.count
            return .success("{\"count\":\(count)}")
        case "track.get_selected":
            return getSelectedTrack()

        // MARK: - Track mutations
        case "track.select":
            return selectTrack(params: params)
        case "track.select_range":
            return selectTrackRange(params: params)
        case "track.set_mute":
            return setTrackToggle(params: params, button: "Mute")
        case "track.set_solo":
            return setTrackToggle(params: params, button: "Solo")
        case "track.set_arm":
            return setTrackToggle(params: params, button: "Record")
        case "track.rename":
            return renameTrack(params: params)
        case "track.set_color":
            return .error("Track color setting not supported via AX")
        case "track.library_is_open":
            return libraryIsOpen()
        case "track.select_library_patch":
            return selectLibraryPatch(params: params)

        // MARK: - Mixer reads
        case "mixer.get_state":
            return getMixerState()
        case "mixer.get_channel_strip":
            return getChannelStrip(params: params)

        // MARK: - Mixer mutations
        case "mixer.set_volume":
            return setMixerValue(params: params, target: .volume)
        case "mixer.set_pan":
            return setMixerValue(params: params, target: .pan)
        case "mixer.set_send":
            return .error("Send adjustment not yet implemented via AX")
        case "mixer.set_input", "mixer.set_output":
            return .error("I/O routing not yet implemented via AX")
        case "mixer.toggle_eq":
            return .error("EQ toggle not yet implemented via AX")
        case "mixer.reset_strip":
            return .error("Strip reset not yet implemented via AX")

        // MARK: - Navigation
        case "nav.get_markers":
            return .error("Marker reading not yet implemented via AX")
        case "nav.rename_marker":
            return .error("Marker renaming not yet implemented via AX")

        // MARK: - Project
        case "project.get_info":
            return getProjectInfo()

        // MARK: - Regions
        case "region.get_regions":
            return .error("Region reading not yet implemented via AX")
        case "region.select", "region.loop", "region.set_name", "region.move", "region.resize":
            return .error("Region operations not yet implemented via AX")

        // MARK: - Plugins
        case "plugin.list", "plugin.insert", "plugin.bypass", "plugin.remove":
            return .error("Plugin operations not yet implemented via AX")

        // MARK: - Automation
        case "automation.get_mode":
            return .error("Automation mode reading not yet implemented via AX")
        case "automation.set_mode":
            return .error("Automation mode setting not yet implemented via AX")

        default:
            return .error("Unsupported AX operation: \(operation)")
        }
    }

    func healthCheck() async -> ChannelHealth {
        guard AXIsProcessTrusted() else {
            return .unavailable("Accessibility not trusted — add this process in System Preferences")
        }
        guard ProcessUtils.isLogicProRunning else {
            return .unavailable("Logic Pro is not running")
        }
        // Quick smoke test: can we reach the app root?
        guard AXLogicProElements.appRoot() != nil else {
            return .unavailable("Cannot access Logic Pro AX element")
        }
        return .healthy(detail: "AX connected to Logic Pro")
    }

    // MARK: - Transport

    private func getTransportState() -> ChannelResult {
        guard let transport = AXLogicProElements.getTransportBar() else {
            return .error("Cannot locate transport bar")
        }
        let state = AXValueExtractors.extractTransportState(from: transport)
        return encodeResult(state)
    }

    private func toggleTransportButton(named name: String) -> ChannelResult {
        guard let button = AXLogicProElements.findTransportButton(named: name) else {
            return .error("Cannot find transport button: \(name)")
        }
        guard AXHelpers.performAction(button, kAXPressAction) else {
            return .error("Failed to press transport button: \(name)")
        }
        return .success("{\"toggled\":\"\(name)\"}")
    }

    private func setTempo(params: [String: String]) -> ChannelResult {
        guard let tempoStr = params["tempo"], let _ = Double(tempoStr) else {
            return .error("Missing or invalid 'tempo' parameter")
        }
        guard let transport = AXLogicProElements.getTransportBar() else {
            return .error("Cannot locate transport bar")
        }
        // Find the tempo text field and set its value
        let texts = AXHelpers.findAllDescendants(of: transport, role: kAXTextFieldRole, maxDepth: 4)
        for field in texts {
            let desc = AXHelpers.getDescription(field)?.lowercased() ?? ""
            if desc.contains("tempo") || desc.contains("bpm") {
                AXHelpers.setAttribute(field, kAXValueAttribute, tempoStr as CFTypeRef)
                AXHelpers.performAction(field, kAXConfirmAction)
                return .success("{\"tempo\":\(tempoStr)}")
            }
        }
        return .error("Cannot locate tempo field")
    }

    private func setCycleRange(params: [String: String]) -> ChannelResult {
        // Cycle range setting via AX is fragile — requires locating the cycle locators
        guard let _ = params["start"], let _ = params["end"] else {
            return .error("Missing 'start' and/or 'end' parameters")
        }
        return .error("Cycle range setting not yet fully implemented via AX")
    }

    // MARK: - Tracks

    private func getTracks() -> ChannelResult {
        let headers = AXLogicProElements.allTrackHeaders()
        if headers.isEmpty {
            return .error("No track headers found — is a project open?")
        }
        var tracks: [TrackState] = []
        for (index, header) in headers.enumerated() {
            let track = AXValueExtractors.extractTrackState(from: header, index: index)
            tracks.append(track)
        }
        return encodeResult(tracks)
    }

    private func getSelectedTrack() -> ChannelResult {
        let headers = AXLogicProElements.allTrackHeaders()
        for (index, header) in headers.enumerated() {
            if AXValueExtractors.extractSelectedState(header) == true {
                let track = AXValueExtractors.extractTrackState(from: header, index: index)
                return encodeResult(track)
            }
        }
        return .error("No track is currently selected")
    }

    private func selectTrack(params: [String: String]) -> ChannelResult {
        guard let indexStr = params["index"], let index = Int(indexStr) else {
            return .error("Missing or invalid 'index' parameter")
        }
        guard let header = AXLogicProElements.findTrackHeader(at: index) else {
            return .error("Track at index \(index) not found")
        }
        guard let frame = AXHelpers.getFrame(header) else {
            return .error("Cannot get frame for track \(index)")
        }
        clickTrackHeader(at: CGPoint(x: frame.midX, y: frame.midY))
        return .success("{\"selected\":\(index)}")
    }

    private func selectTrackRange(params: [String: String]) -> ChannelResult {
        guard let start = params["start"].flatMap(Int.init),
              let end   = params["end"].flatMap(Int.init) else {
            return .error("select_range requires 'start' and 'end' indices")
        }
        guard let pid = ProcessUtils.logicProPID() else {
            return .error("Logic Pro is not running")
        }
        guard let firstHeader = AXLogicProElements.findTrackHeader(at: start),
              let firstFrame  = AXHelpers.getFrame(firstHeader) else {
            return .error("Cannot find track at index \(start)")
        }
        // Click the first track to select it
        clickTrackHeader(at: CGPoint(x: firstFrame.midX, y: firstFrame.midY))
        // Extend selection downward with Shift+Down arrow for each additional track
        let steps = end - start
        guard steps > 0 else { return .success("{\"selected_range\":[\(start),\(end)]}") }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return .error("Failed to create CGEventSource")
        }
        for _ in 0..<steps {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 125, keyDown: true),
                  let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 125, keyDown: false) else { continue }
            keyDown.flags = .maskShift
            keyUp.flags   = .maskShift
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
            Thread.sleep(forTimeInterval: 0.05)
        }
        Thread.sleep(forTimeInterval: 0.1)
        return .success("{\"selected_range\":[\(start),\(end)]}")
    }

    private func clickTrackHeader(at point: CGPoint) {
        if let pid = ProcessUtils.logicProPID(),
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
            Thread.sleep(forTimeInterval: 0.05)
        }
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up   = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,   mouseCursorPosition: point, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func setTrackToggle(params: [String: String], button buttonName: String) -> ChannelResult {
        guard let indexStr = params["index"], let index = Int(indexStr) else {
            return .error("Missing or invalid 'index' parameter")
        }
        let finder: (Int) -> AXUIElement? = switch buttonName {
        case "Mute": AXLogicProElements.findTrackMuteButton
        case "Solo": AXLogicProElements.findTrackSoloButton
        case "Record": AXLogicProElements.findTrackArmButton
        default: { _ in nil }
        }
        guard let button = finder(index) else {
            return .error("Cannot find \(buttonName) button on track \(index)")
        }

        // Determine desired on/off state from params (key name varies by button type)
        let paramName: String
        switch buttonName {
        case "Record": paramName = "armed"
        case "Mute":   paramName = "muted"
        case "Solo":   paramName = "soloed"
        default:       paramName = "enabled"
        }
        if let rawDesired = params[paramName] {
            let desired = (rawDesired == "true" || rawDesired == "1")
            // Read current state so we only press if the state needs to change.
            // Logic Pro arm/mute/solo buttons are AXCheckBox; value is 0 (off) or 1 (on).
            if let raw = AXHelpers.getValue(button) as? NSNumber {
                let current = raw.intValue != 0
                if current == desired {
                    return .success("{\"track\":\(index),\"button\":\"\(buttonName)\",\"state\":\(desired),\"changed\":false}")
                }
            }
        }

        guard AXHelpers.performAction(button, kAXPressAction) else {
            return .error("Failed to click \(buttonName) on track \(index)")
        }
        return .success("{\"track\":\(index),\"toggled\":\"\(buttonName)\"}")
    }

    // MARK: - Library / instrument selection

    private func libraryIsOpen() -> ChannelResult {
        let open = AXLogicProElements.findLibraryPanel() != nil
        return .success("{\"open\":\(open)}")
    }

    private func selectLibraryPatch(params: [String: String]) -> ChannelResult {
        guard let patch = params["patch"], !patch.isEmpty else {
            return .error("Missing 'patch' parameter")
        }
        guard let panel = AXLogicProElements.findLibraryPanel() else {
            return .error("Library panel not found — is the Library open?")
        }

        // Step 1: check first column (categories)
        let categories = AXLogicProElements.findLibraryItems(in: panel, column: 0)
        guard !categories.isEmpty else {
            return .error("Library browser is empty")
        }

        // If the search term matches a category directly, click it and load
        if let catMatch = categories.first(where: { $0.name.localizedCaseInsensitiveContains(patch) }) {
            return clickLibraryElement(catMatch)
        }

        // Step 2: navigate each category looking for a patch match in column 2
        // Priority: try drum-related categories first to avoid a full scan
        let preferred = ["Electronic Drums", "Acoustic Drums", "Percussion", "Synthesizer", "Bass"]
        let orderedCategories = categories.sorted { a, _ in preferred.contains(a.name) }

        for category in orderedCategories {
            guard let frame = AXHelpers.getFrame(category.element) else { continue }
            clickAt(point: CGPoint(x: frame.midX, y: frame.midY))
            Thread.sleep(forTimeInterval: 0.35)

            let patches = AXLogicProElements.findLibraryItems(in: panel, column: -1)
            // Skip if still on the category column (no second column loaded yet)
            guard patches.first?.name != categories.first?.name else { continue }

            if let patchMatch = patches.first(where: { $0.name.localizedCaseInsensitiveContains(patch) }) {
                return clickLibraryElement(patchMatch)
            }
        }

        // Not found — report what's visible in the last column
        let lastItems = AXLogicProElements.findLibraryItems(in: panel, column: -1)
        let preview = lastItems.prefix(8).map { $0.name }.joined(separator: ", ")
        return .error("Patch '\(patch)' not found. Last column: \(preview.isEmpty ? "(none)" : preview)")
    }

    private func clickLibraryElement(_ item: (element: AXUIElement, name: String)) -> ChannelResult {
        guard let frame = AXHelpers.getFrame(item.element) else {
            return .error("Cannot click '\(item.name)' — no frame available")
        }
        clickAt(point: CGPoint(x: frame.midX, y: frame.midY))
        Thread.sleep(forTimeInterval: 0.4)
        return .success("{\"loaded\":\"\(item.name)\"}")
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = [], to pid: pid_t) {
        guard let src = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags   = flags
        down.postToPid(pid)
        up.postToPid(pid)
    }

    private func clickAt(point: CGPoint) {
        if let pid = ProcessUtils.logicProPID(),
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
            Thread.sleep(forTimeInterval: 0.05)
        }
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up   = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,   mouseCursorPosition: point, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func renameTrack(params: [String: String]) -> ChannelResult {
        guard let indexStr = params["index"], let index = Int(indexStr),
              let name = params["name"] else {
            return .error("Missing 'index' or 'name' parameter")
        }
        // Click the track header to select it so the Inspector reflects it
        if let header = AXLogicProElements.findTrackHeader(at: index),
           let frame = AXHelpers.getFrame(header) {
            clickTrackHeader(at: CGPoint(x: frame.midX, y: frame.midY))
        }
        guard let field = AXLogicProElements.findTrackNameField(trackIndex: index) else {
            return .error("Cannot find name field for track \(index)")
        }
        AXHelpers.performAction(field, kAXPressAction)
        AXHelpers.setAttribute(field, kAXValueAttribute, name as CFTypeRef)
        AXHelpers.performAction(field, kAXConfirmAction)
        return .success("{\"track\":\(index),\"name\":\"\(name)\"}")
    }

    // MARK: - Mixer

    private enum MixerTarget {
        case volume
        case pan
    }

    private func getMixerState() -> ChannelResult {
        guard let mixer = AXLogicProElements.getMixerArea() else {
            return .error("Cannot locate mixer — is it visible?")
        }
        let strips = AXHelpers.getChildren(mixer)
        var channelStrips: [ChannelStripState] = []

        for (index, strip) in strips.enumerated() {
            let sliders = AXHelpers.findAllDescendants(of: strip, role: kAXSliderRole, maxDepth: 4)
            let volume = sliders.first.flatMap { AXValueExtractors.extractSliderValue($0) } ?? 0.0
            let pan = sliders.count > 1
                ? AXValueExtractors.extractSliderValue(sliders[1]) ?? 0.0
                : 0.0

            channelStrips.append(ChannelStripState(
                trackIndex: index,
                volume: volume,
                pan: pan
            ))
        }
        return encodeResult(channelStrips)
    }

    private func getChannelStrip(params: [String: String]) -> ChannelResult {
        guard let indexStr = params["index"], let index = Int(indexStr) else {
            return .error("Missing or invalid 'index' parameter")
        }
        guard let mixer = AXLogicProElements.getMixerArea() else {
            return .error("Cannot locate mixer — is it visible?")
        }
        let strips = AXHelpers.getChildren(mixer)
        guard index >= 0 && index < strips.count else {
            return .error("Channel strip index \(index) out of range")
        }
        let strip = strips[index]
        let sliders = AXHelpers.findAllDescendants(of: strip, role: kAXSliderRole, maxDepth: 4)
        let volume = sliders.first.flatMap { AXValueExtractors.extractSliderValue($0) } ?? 0.0
        let pan = sliders.count > 1
            ? AXValueExtractors.extractSliderValue(sliders[1]) ?? 0.0
            : 0.0

        let state = ChannelStripState(trackIndex: index, volume: volume, pan: pan)
        return encodeResult(state)
    }

    private func setMixerValue(params: [String: String], target: MixerTarget) -> ChannelResult {
        guard let indexStr = params["index"], let index = Int(indexStr),
              let valueStr = params["value"], let value = Double(valueStr) else {
            return .error("Missing 'index' or 'value' parameter")
        }
        let element: AXUIElement?
        switch target {
        case .volume:
            element = AXLogicProElements.findFader(trackIndex: index)
        case .pan:
            element = AXLogicProElements.findPanKnob(trackIndex: index)
        }
        guard let slider = element else {
            return .error("Cannot find \(target) control for track \(index)")
        }
        AXHelpers.setAttribute(slider, kAXValueAttribute, NSNumber(value: value))
        let label = target == .volume ? "volume" : "pan"
        return .success("{\"\(label)\":\(value),\"track\":\(index)}")
    }

    // MARK: - Project

    private func getProjectInfo() -> ChannelResult {
        guard let window = AXLogicProElements.mainWindow() else {
            return .error("Cannot locate Logic Pro main window")
        }
        let title = AXHelpers.getTitle(window) ?? "Unknown"
        var info = ProjectInfo()
        info.name = title
        info.lastUpdated = Date()
        return encodeResult(info)
    }

    // MARK: - JSON encoding

    private func encodeResult<T: Encodable>(_ value: T) -> ChannelResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(value)
            guard let json = String(data: data, encoding: .utf8) else {
                return .error("Failed to encode result to UTF-8")
            }
            return .success(json)
        } catch {
            return .error("JSON encoding failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum AccessibilityError: Error, CustomStringConvertible {
    case notTrusted

    var description: String {
        switch self {
        case .notTrusted:
            return "Process is not trusted for Accessibility. Add it in System Preferences > Privacy & Security > Accessibility."
        }
    }
}
