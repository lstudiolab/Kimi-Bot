import Foundation

actor JSONStore {
    private let fileURL: URL
    private(set) var data: [String: JSONValue]

    init(directory: URL, filename: String = "kimi.json") throws {
        fileURL = directory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let bytes = try Data(contentsOf: fileURL)
            data = try JSONDecoder().decode([String: JSONValue].self, from: bytes)
        } else {
            data = [:]
        }
    }

    func value(for key: String) -> JSONValue? { data[key] }

    func set(_ value: JSONValue?, for key: String) throws {
        data[key] = value
        try save()
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(data)
        try bytes.write(to: fileURL, options: .atomic)
    }
}
