import Foundation

struct KimiAppearance: Codable, Sendable, Equatable {
    var buttonStyle: Int
    var embedColor: Int

    static let defaultValue = KimiAppearance(buttonStyle: KimiUI.buttonStyle, embedColor: KimiUI.grey)

    static let buttonStyles: [(label: String, value: Int)] = [
        ("Primary", 1),
        ("Secondary", 2),
        ("Success", 3),
        ("Danger", 4),
    ]

    static let embedColors: [(label: String, value: Int)] = [
        ("Grey", 0x808080),
        ("Blurple", 0x5865F2),
        ("Green", 0x57F287),
        ("Red", 0xED4245),
        ("Orange", 0xE67E22),
    ]

    static func load(store: PersistentStore, guildID: String) async -> KimiAppearance {
        await store.get("control.appearance." + guildID, as: KimiAppearance.self) ?? .defaultValue
    }

    var buttonStyleName: String {
        Self.buttonStyles.first(where: { $0.value == buttonStyle })?.label ?? "Primary"
    }

    var embedColorName: String {
        Self.embedColors.first(where: { $0.value == embedColor })?.label ?? "Grey"
    }

    var embedColorHex: String {
        String(format: "#%06X", embedColor)
    }

    func rows() -> [[String: Any]] {
        [
            KimiUI.row([
                KimiUI.stringSelect(
                    id: "control:appearance:button-style",
                    placeholder: "Button style · " + buttonStyleName,
                    options: Self.buttonStyles.map {
                        ["label": $0.label, "value": String($0.value)]
                    })
            ]),
            KimiUI.row([
                KimiUI.stringSelect(
                    id: "control:appearance:embed-color",
                    placeholder: "Embed color · " + embedColorName,
                    options: Self.embedColors.map {
                        ["label": $0.label, "value": String($0.value)]
                    })
            ]),
            KimiUI.row([
                KimiUI.button(id: "settings:home", label: "Back to Control Center")
            ]),
        ]
    }

    var summary: String {
        "Button style: " + buttonStyleName
            + "\nEmbed color: " + embedColorName + " (" + embedColorHex + ")"
    }
}

extension KimiRuntime {
    func editThemedInteraction(
        _ app: String, _ token: String, _ content: String,
        _ components: [[String: Any]]? = nil, guildID: String
    ) async throws {
        let appearance = await KimiAppearance.load(store: store, guildID: guildID)
        if let components {
            try await rest.editKimiInteraction(
                app, token, content, components,
                embedColor: appearance.embedColor, buttonStyle: appearance.buttonStyle)
        } else {
            try await rest.editKimiInteraction(
                app, token, content,
                embedColor: appearance.embedColor, buttonStyle: appearance.buttonStyle)
        }
    }

    func authorizeControlCenter(_ actorID: String, member: [String: Any], guildID: String) async throws {
        let owner = try await rest.ownerID(guildID)
        let permissions = UInt64(member["permissions"] as? String ?? "") ?? 0
        guard owner == actorID || permissions & (1 << 5) != 0 else {
            throw KimiError.configuration(
                "Only the server owner or a member with Manage Server can customize Kimi.")
        }
    }

    func showAppearancePanel(
        _ app: String, _ token: String, guildID: String,
        appearance: KimiAppearance, notice: String = "Customize Kimi's appearance."
    ) async throws {
        try await editThemedInteraction(
            app, token, "Kimi Appearance\n" + notice + "\n\n" + appearance.summary,
            appearance.rows(), guildID: guildID)
    }
}
