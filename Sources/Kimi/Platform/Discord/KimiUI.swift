import Foundation

enum KimiUI {
    static let grey = 0x808080
    static func embed(title: String, description: String) -> [String: Any] {
        ["color": grey, "title": String(title.prefix(256)), "description": String(description.prefix(4096))]
    }
    static func button(id: String, label: String, style: Int = 2, disabled: Bool = false) -> [String: Any] {
        ["type": 2, "style": style, "custom_id": id, "label": String(label.prefix(80)), "disabled": disabled]
    }
    static func row(_ components: [[String: Any]]) -> [String: Any] {
        ["type": 1, "components": Array(components.prefix(5))]
    }
    static func buttonRows(_ buttons: [[String: Any]], perRow: Int = 5) -> [[String: Any]] {
        let width = max(1, min(5, perRow))
        return stride(from: 0, to: buttons.count, by: width).map { start in
            row(Array(buttons[start..<min(start + width, buttons.count)]))
        }
    }
    static func validateMessageComponents(_ rows: [[String: Any]]) throws {
        guard rows.count <= 5 else {
            throw KimiError.configuration("This panel has more than Discord's 5 action-row limit.")
        }
        for row in rows {
            guard (row["type"] as? Int) == 1,
                let items = row["components"] as? [[String: Any]],
                !items.isEmpty, items.count <= 5
            else {
                throw KimiError.configuration("This panel contains an invalid Discord action row.")
            }
            if items.contains(where: { ($0["type"] as? Int) != 2 }) && items.count != 1 {
                throw KimiError.configuration("Select menus and text inputs must occupy their own action row.")
            }
        }
    }
    static func stringSelect(
        id: String, placeholder: String, options: [[String: Any]], minimum: Int = 0, maximum: Int = 1
    ) -> [String: Any] {
        [
            "type": 3, "custom_id": id, "placeholder": String(placeholder.prefix(150)), "min_values": max(0, minimum),
            "max_values": max(1, min(25, maximum)), "options": Array(options.prefix(25)),
        ]
    }
    static func channelSelect(id: String, placeholder: String, channelTypes: [Int] = [0]) -> [String: Any] {
        [
            "type": 8,
            "custom_id": id,
            "placeholder": String(placeholder.prefix(150)),
            "channel_types": channelTypes,
            "min_values": 0,
            "max_values": 1,
        ]
    }
    static func roleSelect(id: String, placeholder: String) -> [String: Any] {
        [
            "type": 6,
            "custom_id": id,
            "placeholder": String(placeholder.prefix(150)),
            "min_values": 0,
            "max_values": 1,
        ]
    }
    static func textInput(
        id: String, label: String, value: String = "", style: Int = 1, required: Bool = true, maximum: Int = 1000
    ) -> [String: Any] {
        var item: [String: Any] = [
            "type": 4, "custom_id": id, "label": String(label.prefix(45)), "style": style, "required": required,
            "max_length": max(1, min(4000, maximum)),
        ]
        if !value.isEmpty { item["value"] = String(value.prefix(maximum)) }
        return item
    }
    static func modal(id: String, title: String, inputs: [[String: Any]]) -> [String: Any] {
        ["custom_id": id, "title": String(title.prefix(45)), "components": inputs.prefix(5).map { row([$0]) }]
    }
    static func safeMentions() -> [String: Any] { ["parse": []] }
    static func message(_ content: String, components: [[String: Any]] = []) -> [String: Any] {
        ["content": String(content.prefix(1900)), "components": components, "allowed_mentions": safeMentions()]
    }
}
