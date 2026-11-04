import Foundation

enum KimiUI {
    static let grey = 0x808080
    static func embed(title: String, description: String) -> [String: Any] {
        ["color": grey, "title": DiscordText.prefixUTF16(title, limit: 256), "description": DiscordText.prefixUTF16(description, limit: 4096)]
    }
    static func button(id: String, label: String, style: Int = 2, disabled: Bool = false) -> [String: Any] {
        ["type": 2, "style": max(1, min(5, style)), "custom_id": DiscordText.prefixUTF16(id, limit: 100), "label": DiscordText.prefixUTF16(label, limit: 80), "disabled": disabled]
    }
    static func row(_ components: [[String: Any]]) -> [String: Any] {
        ["type": 1, "components": Array(components.prefix(5))]
    }
    static func buttonRows(_ buttons: [[String: Any]], perRow: Int = 5) -> [[String: Any]] {
        let width = max(1, min(5, perRow))
        let safeButtons = Array(buttons.prefix(25))
        return stride(from: 0, to: safeButtons.count, by: width).map { start in
            row(Array(safeButtons[start..<min(start + width, safeButtons.count)]))
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
            if let menu = items.first, let type = menu["type"] as? Int, [3, 5, 6, 7, 8].contains(type) {
                let minimum = menu["min_values"] as? Int ?? 0
                let maximum = menu["max_values"] as? Int ?? 1
                guard minimum >= 0, maximum >= 1, minimum <= maximum, maximum <= 25 else {
                    throw KimiError.configuration("A select menu has invalid minimum or maximum selections.")
                }
                if type == 3 {
                    let options = menu["options"] as? [[String: Any]] ?? []
                    guard !options.isEmpty, options.count <= 25, maximum <= options.count else {
                        throw KimiError.configuration("A string select menu must have 1–25 options and a valid selection limit.")
                    }
                }
            }
        }
    }
    static func stringSelect(
        id: String, placeholder: String, options: [[String: Any]], minimum: Int = 0, maximum: Int = 1
    ) -> [String: Any] {
        let safeOptions = Array(options.prefix(25)).map { option -> [String: Any] in
            var value = option
            if let label = option["label"] as? String {
                value["label"] = DiscordText.prefixUTF16(label, limit: 100)
            }
            if let optionValue = option["value"] as? String {
                value["value"] = DiscordText.prefixUTF16(optionValue, limit: 100)
            }
            if let description = option["description"] as? String {
                value["description"] = DiscordText.prefixUTF16(description, limit: 100)
            }
            return value
        }
        let maximumValues = max(1, min(25, min(safeOptions.count, maximum)))
        let minimumValues = max(0, min(minimum, maximumValues))
        return [
            "type": 3, "custom_id": DiscordText.prefixUTF16(id, limit: 100),
            "placeholder": DiscordText.prefixUTF16(placeholder, limit: 150), "min_values": minimumValues,
            "max_values": maximumValues, "options": safeOptions,
        ]
    }
    static func channelSelect(id: String, placeholder: String, channelTypes: [Int] = [0]) -> [String: Any] {
        [
            "type": 8,
            "custom_id": id,
            "placeholder": DiscordText.prefixUTF16(placeholder, limit: 150),
            "channel_types": channelTypes,
            "min_values": 0,
            "max_values": 1,
        ]
    }
    static func roleSelect(id: String, placeholder: String) -> [String: Any] {
        [
            "type": 6,
            "custom_id": id,
            "placeholder": DiscordText.prefixUTF16(placeholder, limit: 150),
            "min_values": 0,
            "max_values": 1,
        ]
    }
    static func textInput(
        id: String, label: String, value: String = "", style: Int = 1, required: Bool = true, maximum: Int = 1000
    ) -> [String: Any] {
        var item: [String: Any] = [
            "type": 4, "custom_id": DiscordText.prefixUTF16(id, limit: 100), "label": DiscordText.prefixUTF16(label, limit: 45),
            "style": max(1, min(2, style)), "required": required,
            "max_length": max(1, min(4000, maximum)),
        ]
        if !value.isEmpty { item["value"] = DiscordText.prefixUTF16(value, limit: max(1, min(4000, maximum))) }
        return item
    }
    static func modal(id: String, title: String, inputs: [[String: Any]]) -> [String: Any] {
        ["custom_id": DiscordText.prefixUTF16(id, limit: 100), "title": DiscordText.prefixUTF16(title, limit: 45), "components": inputs.prefix(5).map { row([$0]) }]
    }
    static func safeMentions() -> [String: Any] { ["parse": []] }
    static func message(_ content: String, components: [[String: Any]] = []) -> [String: Any] {
        ["content": DiscordText.prefixUTF16(content, limit: 1900), "components": components, "allowed_mentions": safeMentions()]
    }
}
