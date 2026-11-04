import Foundation

/// Incremental framing for Discord Gateway JSON payloads.
///
/// WebSocket receive APIs normally return complete messages, but some
/// FoundationNetworking implementations can surface fragmented payloads.
/// This parser accepts arbitrary chunks and extracts one complete top-level
/// JSON object at a time without confusing braces inside quoted strings.
enum GatewayJSONFramer {
    static func takeFrame(from buffer: inout Data) -> Data? {
        let bytes = [UInt8](buffer)
        var start: Int?
        var depth = 0
        var inString = false
        var escaped = false

        for index in bytes.indices {
            let byte = bytes[index]
            if start == nil {
                if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                    continue
                }
                guard byte == 0x7B else {
                    // Skip a corrupt prefix and continue immediately if another frame is already buffered.
                    if let nextObject = bytes[(index + 1)...].firstIndex(of: 0x7B) {
                        buffer.removeFirst(nextObject)
                        return takeFrame(from: &buffer)
                    }
                    buffer.removeAll(keepingCapacity: true)
                    return nil
                }
                start = index
                depth = 1
                continue
            }

            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
                continue
            }

            if byte == 0x22 {
                inString = true
            } else if byte == 0x7B {
                depth += 1
            } else if byte == 0x7D {
                depth -= 1
                if depth == 0, let start {
                    let frame = Data(bytes[start...index])
                    buffer.removeFirst(index + 1)
                    return frame
                }
            }
        }
        return nil
    }
}
