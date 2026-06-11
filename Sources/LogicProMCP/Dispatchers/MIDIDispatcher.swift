import Foundation
import MCP

struct MIDIDispatcher {
    static let tool = Tool(
        name: "logic_midi",
        description: """
            MIDI operations in Logic Pro. \
            Commands: send_note, send_chord, send_cc, send_program_change, \
            send_pitch_bend, send_aftertouch, send_sysex, \
            create_virtual_port, mmc_play, mmc_stop, mmc_record, mmc_locate. \
            Params by command: \
            send_note -> { note: Int, velocity: Int, channel: Int, duration_ms: Int }; \
            send_chord -> { notes: [Int], velocity: Int, channel: Int, duration_ms: Int }; \
            send_cc -> { controller: Int, value: Int, channel: Int }; \
            send_program_change -> { program: Int, channel: Int }; \
            send_pitch_bend -> { value: Int, channel: Int } (-8192 to 8191); \
            send_aftertouch -> { value: Int, channel: Int }; \
            send_sysex -> { bytes: [Int] } or { data: String } (hex); \
            mmc_locate -> { bar: Int } or { time: "HH:MM:SS:FF" }; \
            create_virtual_port -> { name: String }
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "description": .string("MIDI command to execute"),
                ]),
                "params": .object([
                    "type": .string("object"),
                    "description": .string("Command-specific parameters"),
                ]),
            ]),
            "required": .array([.string("command")]),
        ])
    )

    static func handle(
        command: String,
        params: [String: Value],
        router: ChannelRouter,
        cache: StateCache
    ) async -> CallTool.Result {
        switch command {
        case "send_note":
            let note = params["note"]?.intValue ?? 60
            let velocity = params["velocity"]?.intValue ?? 100
            let channel = params["channel"]?.intValue ?? 1
            let durationMs = params["duration_ms"]?.intValue ?? 500
            let result = await router.route(
                operation: "midi.send_note",
                params: [
                    "note": String(note),
                    "velocity": String(velocity),
                    "channel": String(channel),
                    "duration_ms": String(durationMs),
                ]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "send_chord":
            // Accept either array of ints or comma-separated string
            let notesStr: String
            if let arr = params["notes"]?.arrayValue {
                notesStr = arr.compactMap { $0.intValue }.map(String.init).joined(separator: ",")
            } else {
                notesStr = params["notes"]?.stringValue ?? ""
            }
            let velocity = params["velocity"]?.intValue ?? 100
            let channel = params["channel"]?.intValue ?? 1
            let durationMs = params["duration_ms"]?.intValue ?? 500
            let result = await router.route(
                operation: "midi.send_chord",
                params: [
                    "notes": notesStr,
                    "velocity": String(velocity),
                    "channel": String(channel),
                    "duration_ms": String(durationMs),
                ]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "send_cc":
            let controller = params["controller"]?.intValue ?? 0
            let value = params["value"]?.intValue ?? 0
            let channel = params["channel"]?.intValue ?? 1
            let result = await router.route(
                operation: "midi.send_cc",
                params: [
                    "controller": String(controller),
                    "value": String(value),
                    "channel": String(channel),
                ]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "send_program_change":
            let program = params["program"]?.intValue ?? 0
            let channel = params["channel"]?.intValue ?? 1
            let result = await router.route(
                operation: "midi.send_program_change",
                params: ["program": String(program), "channel": String(channel)]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "send_pitch_bend":
            let value = params["value"]?.intValue ?? 0
            let channel = params["channel"]?.intValue ?? 1
            let result = await router.route(
                operation: "midi.send_pitch_bend",
                params: ["value": String(value), "channel": String(channel)]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "send_aftertouch":
            let value = params["value"]?.intValue ?? 0
            let channel = params["channel"]?.intValue ?? 1
            let result = await router.route(
                operation: "midi.send_aftertouch",
                params: ["value": String(value), "channel": String(channel)]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "send_sysex":
            let data: String
            if let bytes = params["bytes"]?.arrayValue {
                data = bytes.compactMap { $0.intValue }
                    .map { String(format: "%02X", $0) }
                    .joined(separator: " ")
            } else {
                data = params["data"]?.stringValue ?? ""
            }
            let result = await router.route(
                operation: "midi.send_sysex",
                params: ["data": data]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "create_virtual_port":
            let name = params["name"]?.stringValue ?? "Virtual Port"
            let result = await router.route(
                operation: "midi.create_virtual_port",
                params: ["name": name]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "mmc_play":
            let result = await router.route(operation: "mmc.play")
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "mmc_stop":
            let result = await router.route(operation: "mmc.stop")
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "mmc_record":
            let result = await router.route(operation: "mmc.record_strobe")
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "mmc_locate":
            if let bar = params["bar"]?.intValue {
                let result = await router.route(
                    operation: "mmc.locate",
                    params: ["bar": String(bar)]
                )
                return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)
            }
            let time = params["time"]?.stringValue ?? "00:00:00:00"
            let result = await router.route(
                operation: "mmc.locate",
                params: ["time": time]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "record_pattern":
            return await recordPattern(params: params, router: router)

        default:
            return CallTool.Result(
                content: [.text(text: "Unknown MIDI command: \(command). Available: send_note, send_chord, send_cc, send_program_change, send_pitch_bend, send_aftertouch, send_sysex, create_virtual_port, mmc_play, mmc_stop, mmc_record, mmc_locate, record_pattern", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    // MARK: - Pattern Recording

    /// Records a drum pattern internally with Swift-level timing (no MCP round-trip latency).
    /// GM drum note numbers: 36=kick, 38=snare, 42=closed hi-hat, 46=open hi-hat, 49=crash.
    /// Params: track (index), tempo (BPM), bars (number of bars to record, default 1), channel.
    private static func recordPattern(
        params: [String: Value],
        router: ChannelRouter
    ) async -> CallTool.Result {
        let trackIndex = params["track"]?.intValue ?? 2
        let tempo: Double  = params["tempo"]?.doubleValue ?? 120.0
        let bars: Int      = params["bars"]?.intValue ?? (params["beats"]?.intValue ?? 2) / 4
        let totalBars      = max(1, bars)
        let channel        = params["channel"]?.intValue ?? 1

        let beatMs         = 60_000.0 / tempo
        let totalBeats     = Double(totalBars * 4)   // assumes 4/4
        let noteDurMs      = max(40, Int(beatMs * 0.08))

        // Build pattern: kick on beats 1&3, snare on 2&4, hi-hat on every 8th.
        struct Hit { let beat: Double; let notes: String }
        var pattern: [Hit] = []
        for bar in 0..<totalBars {
            let base = Double(bar * 4)
            pattern += [
                Hit(beat: base + 0.0, notes: "36,42"),
                Hit(beat: base + 0.5, notes: "42"),
                Hit(beat: base + 1.0, notes: "38,42"),
                Hit(beat: base + 1.5, notes: "42"),
                Hit(beat: base + 2.0, notes: "36,42"),
                Hit(beat: base + 2.5, notes: "42"),
                Hit(beat: base + 3.0, notes: "38,42"),
                Hit(beat: base + 3.5, notes: "42"),
            ]
        }

        // Stop → close Piano Roll if open → rewind to bar 1 → arm → record
        _ = await router.route(operation: "transport.stop")
        try? await Task.sleep(nanoseconds: 150_000_000)
        _ = await router.route(operation: "transport.escape")          // dismiss any dialog/focus
        try? await Task.sleep(nanoseconds: 100_000_000)
        // Rewind enough bars to guarantee we reach bar 1 (each press = -1 bar)
        for _ in 0..<(totalBars + 4) {
            _ = await router.route(operation: "transport.rewind")
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        _ = await router.route(operation: "track.set_arm",
                               params: ["index": String(trackIndex), "armed": "true"])
        try? await Task.sleep(nanoseconds: 200_000_000)
        _ = await router.route(operation: "transport.record")

        // 100ms settle — enough for Logic to enter record mode
        try? await Task.sleep(nanoseconds: 100_000_000)

        let t0 = DispatchTime.now().uptimeNanoseconds

        for hit in pattern {
            let targetNs = UInt64(hit.beat * beatMs * 1_000_000)
            let elapsed  = DispatchTime.now().uptimeNanoseconds - t0
            if targetNs > elapsed {
                try? await Task.sleep(nanoseconds: targetNs - elapsed)
            }
            _ = await router.route(
                operation: "midi.send_chord",
                params: [
                    "notes":       hit.notes,
                    "velocity":    "90",
                    "channel":     String(channel),
                    "duration_ms": String(noteDurMs),
                ]
            )
        }

        // Wait out the rest of the recording window, then stop
        let endNs   = UInt64(totalBeats * beatMs * 1_000_000)
        let elapsed = DispatchTime.now().uptimeNanoseconds - t0
        if endNs > elapsed {
            try? await Task.sleep(nanoseconds: endNs - elapsed)
        }

        _ = await router.route(operation: "transport.stop")
        try? await Task.sleep(nanoseconds: 300_000_000)
        _ = await router.route(operation: "track.set_arm",
                               params: ["index": String(trackIndex), "armed": "false"])

        // Auto-quantize: open Piano Roll → select all → Q → close Piano Roll
        try? await Task.sleep(nanoseconds: 400_000_000)
        _ = await router.route(operation: "transport.escape")        // clear any focused panel
        try? await Task.sleep(nanoseconds: 150_000_000)
        _ = await router.route(operation: "view.toggle_piano_roll")  // open
        try? await Task.sleep(nanoseconds: 700_000_000)               // wait for it to load
        _ = await router.route(operation: "edit.select_all")          // Cmd+A
        try? await Task.sleep(nanoseconds: 200_000_000)
        _ = await router.route(operation: "edit.quantize")            // Q
        try? await Task.sleep(nanoseconds: 300_000_000)
        _ = await router.route(operation: "view.toggle_piano_roll")  // close

        return CallTool.Result(
            content: [.text(
                text: "{\"recorded\":true,\"bars\":\(totalBars),\"tempo\":\(tempo),\"track\":\(trackIndex)}",
                annotations: nil, _meta: nil)],
            isError: false
        )
    }
}
