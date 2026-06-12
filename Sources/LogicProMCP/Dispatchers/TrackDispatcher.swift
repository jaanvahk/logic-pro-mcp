import Foundation
import MCP

struct TrackDispatcher {
    static let tool = Tool(
        name: "logic_tracks",
        description: """
            Track actions in Logic Pro. \
            Commands: select, create_audio, create_instrument, create_drummer, \
            create_external_midi, delete, duplicate, rename, mute, solo, arm, set_color, \
            set_instrument. \
            Params by command: \
            select -> { index: Int } or { name: String }; \
            rename -> { index: Int, name: String }; \
            mute/solo/arm -> { index: Int, enabled: Bool }; \
            set_color -> { index: Int, color: Int } (Logic color index 0-24); \
            set_instrument -> { index: Int, patch: String } (patch name from Logic Library); \
            create_* -> {} (creates at current position); \
            delete/duplicate -> { index: Int }
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "description": .string("Track command to execute"),
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
        case "select":
            if let index = params["index"]?.intValue {
                let result = await router.route(
                    operation: "track.select",
                    params: ["index": String(index)]
                )
                return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)
            }
            if let name = params["name"]?.stringValue {
                // Find track by name in cache
                let tracks = await cache.getTracks()
                if let track = tracks.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
                    let result = await router.route(
                        operation: "track.select",
                        params: ["index": String(track.id)]
                    )
                    return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)
                }
                return CallTool.Result(content: [.text(text: "No track found matching '\(name)'", annotations: nil, _meta: nil)], isError: true)
            }
            return CallTool.Result(content: [.text(text: "select requires 'index' or 'name' param", annotations: nil, _meta: nil)], isError: true)

        case "create_audio":
            let result = await router.route(operation: "track.create_audio")
            guard result.isSuccess else {
                return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: true)
            }
            if let name = params["name"]?.stringValue, !name.isEmpty {
                return await createAndName(name: name, router: router)
            }
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: false)

        case "create_instrument":
            let result = await router.route(operation: "track.create_instrument")
            guard result.isSuccess else {
                return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: true)
            }
            if let name = params["name"]?.stringValue, !name.isEmpty {
                return await createAndName(name: name, router: router)
            }
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: false)

        case "create_drummer":
            let result = await router.route(operation: "track.create_drummer")
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "create_external_midi":
            let result = await router.route(operation: "track.create_external_midi")
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "delete_range":
            let start = params["start"]?.intValue ?? 0
            let end   = params["end"]?.intValue ?? 0
            guard start > 0 && end >= start else {
                return CallTool.Result(content: [.text(text: "delete_range requires 'start' and 'end' (1-based, end >= start)", annotations: nil, _meta: nil)], isError: true)
            }
            // Delete from end→start so indices stay valid as tracks are removed
            for index in stride(from: end, through: start, by: -1) {
                let sel = await router.route(operation: "track.select", params: ["index": String(index)])
                guard sel.isSuccess else {
                    return CallTool.Result(content: [.text(text: "Failed to select track \(index): \(sel.message)", annotations: nil, _meta: nil)], isError: true)
                }
                let del = await router.route(operation: "track.delete")
                guard del.isSuccess else {
                    return CallTool.Result(content: [.text(text: "Failed to delete track \(index): \(del.message)", annotations: nil, _meta: nil)], isError: true)
                }
            }
            return CallTool.Result(content: [.text(text: "{\"deleted\":\(end - start + 1),\"range\":[\(start),\(end)]}", annotations: nil, _meta: nil)], isError: false)

        case "delete":
            if let index = params["index"]?.intValue {
                let result = await router.route(
                    operation: "track.select",
                    params: ["index": String(index)]
                )
                guard result.isSuccess else {
                    return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: true)
                }
            }
            let result = await router.route(operation: "track.delete")
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "duplicate":
            if let index = params["index"]?.intValue {
                let selectResult = await router.route(
                    operation: "track.select",
                    params: ["index": String(index)]
                )
                guard selectResult.isSuccess else {
                    return CallTool.Result(content: [.text(text: selectResult.message, annotations: nil, _meta: nil)], isError: true)
                }
            }
            let result = await router.route(operation: "track.duplicate")
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "rename":
            let index = params["index"]?.intValue ?? 0
            let name = params["name"]?.stringValue ?? ""
            let result = await router.route(
                operation: "track.rename",
                params: ["index": String(index), "name": name]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "mute":
            let index = params["index"]?.intValue ?? 0
            let enabled = params["enabled"]?.boolValue ?? true
            let result = await router.route(
                operation: "track.set_mute",
                params: ["index": String(index), "muted": String(enabled)]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "solo":
            let index = params["index"]?.intValue ?? 0
            let enabled = params["enabled"]?.boolValue ?? true
            let result = await router.route(
                operation: "track.set_solo",
                params: ["index": String(index), "soloed": String(enabled)]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "arm":
            let index = params["index"]?.intValue ?? 0
            let enabled = params["enabled"]?.boolValue ?? true
            let result = await router.route(
                operation: "track.set_arm",
                params: ["index": String(index), "armed": String(enabled)]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "set_color":
            let index = params["index"]?.intValue ?? 0
            let color = params["color"]?.intValue ?? 0
            let result = await router.route(
                operation: "track.set_color",
                params: ["index": String(index), "color": String(color)]
            )
            return CallTool.Result(content: [.text(text: result.message, annotations: nil, _meta: nil)], isError: !result.isSuccess)

        case "set_instrument":
            return await setInstrument(params: params, router: router)

        default:
            return CallTool.Result(
                content: [.text(text: "Unknown track command: \(command). Available: select, create_audio, create_instrument, create_drummer, create_external_midi, delete, delete_range, duplicate, rename, mute, solo, arm, set_color, set_instrument", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    private static func setInstrument(params: [String: Value], router: ChannelRouter) async -> CallTool.Result {
        let index = params["index"]?.intValue ?? 0
        guard let patch = params["patch"]?.stringValue, !patch.isEmpty else {
            return CallTool.Result(
                content: [.text(text: "set_instrument requires 'patch' param (patch name from Logic Library)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
        // Select the track first so the Library shows its patches
        let selResult = await router.route(operation: "track.select", params: ["index": String(index)])
        guard selResult.isSuccess else {
            return CallTool.Result(content: [.text(text: selResult.message, annotations: nil, _meta: nil)], isError: true)
        }
        try? await Task.sleep(nanoseconds: 150_000_000)

        // Check if Library is already open so we can restore state afterward
        let openCheck = await router.route(operation: "track.library_is_open")
        let wasOpen = openCheck.message.contains("\"open\":true")

        if !wasOpen {
            _ = await router.route(operation: "view.toggle_library")
            try? await Task.sleep(nanoseconds: 400_000_000)   // wait for panel animation
        }

        // Find and click the patch
        let patchResult = await router.route(
            operation: "track.select_library_patch",
            params: ["patch": patch]
        )

        // Restore Library state
        if !wasOpen {
            _ = await router.route(operation: "view.toggle_library")
        }

        return CallTool.Result(
            content: [.text(text: patchResult.message, annotations: nil, _meta: nil)],
            isError: !patchResult.isSuccess
        )
    }

    private static func createAndName(name: String, router: ChannelRouter) async -> CallTool.Result {
        try? await Task.sleep(nanoseconds: 300_000_000)
        let countResult = await router.route(operation: "track.count")
        guard let index = countResult.message.components(separatedBy: "\"count\":").last
                .flatMap({ Int($0.prefix(while: { $0.isNumber })) }) else {
            return CallTool.Result(content: [.text(text: "Created track but could not determine index to rename", annotations: nil, _meta: nil)], isError: false)
        }
        _ = await router.route(operation: "track.rename", params: ["index": String(index), "name": name])
        return CallTool.Result(content: [.text(text: "{\"created\":true,\"name\":\"\(name)\",\"index\":\(index)}", annotations: nil, _meta: nil)], isError: false)
    }
}
