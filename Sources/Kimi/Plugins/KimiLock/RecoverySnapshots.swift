import Foundation

extension RecoveryService {
        func captureChannel(_ guild: String, _ channel: [String: Any]) async {
            guard let id = channel["id"] as? String,
                let data = try? JSONSerialization.data(withJSONObject: channel, options: [.fragmentsAllowed])
            else { return }
            do {
                _ = try await store.updateGuild("recovery.channels", guildID: guild, as: [String: [String: Data]].self) { stored in
                    var all = stored ?? [:]
                    all[guild, default: [:]][id] = data
                    if all[guild, default: [:]].count > 1000 {
                        all[guild] = Dictionary(
                            uniqueKeysWithValues: all[guild, default: [:]].sorted { $0.key < $1.key }.suffix(1000))
                    }
                    return all
                }
            } catch {
                await logger.log("ERROR", "Recovery channel snapshot was not persisted: " + error.localizedDescription)
            }
        }

        func captureRole(_ guild: String, _ role: [String: Any]) async {
            guard let id = role["id"] as? String, id != guild,
                let data = try? JSONSerialization.data(withJSONObject: role, options: [.fragmentsAllowed])
            else { return }
            do {
                _ = try await store.updateGuild("recovery.roles", guildID: guild, as: [String: [String: Data]].self) { stored in
                    var all = stored ?? [:]
                    all[guild, default: [:]][id] = data
                    if all[guild, default: [:]].count > 500 {
                        all[guild] = Dictionary(
                            uniqueKeysWithValues: all[guild, default: [:]].sorted { $0.key < $1.key }.suffix(500))
                    }
                    return all
                }
            } catch {
                await logger.log("ERROR", "Recovery role snapshot was not persisted: " + error.localizedDescription)
            }
        }

        func captureMessage(
            _ guild: String, _ channel: String, _ message: String, _ author: String, _ content: String,
            attachments: [Attachment] = [], authorName: String? = nil, createdAt: Date? = nil
        ) async {
            let now = Date()
            let cutoff = now.addingTimeInterval(-week)
            let snapshotDate = createdAt ?? now
            do {
                try await store.updateGuild("recovery.messages", guildID: guild, as: [String: [Message]].self) { stored in
                    var all = stored ?? [:]
                    let previousRows = all[guild] ?? []
                    let previousIndex = previousRows.firstIndex(where: { $0.id == message })
                    let originalCreatedAt = previousIndex.map { previousRows[$0].createdAt } ?? snapshotDate
                    var rows = previousRows.filter { $0.createdAt >= cutoff }
                    // Editing an old message must not refresh its seven-day retention window.
                    if originalCreatedAt >= cutoff {
                        let updated = Message(
                            id: message, channelID: channel, authorID: author, content: DiscordText.prefixUTF16(content, limit: 4000),
                            createdAt: originalCreatedAt, authorName: authorName,
                            attachments: Array(attachments.prefix(10)))
                        if let index = rows.firstIndex(where: { $0.id == message }) {
                            rows[index] = updated
                        } else {
                            rows.append(updated)
                        }
                    } else {
                        rows.removeAll { $0.id == message }
                    }
                    func encodedSize(_ row: Message) -> Int {
                        (try? JSONEncoder().encode(row).count) ?? row.content.utf8.count
                    }
                    var bytes = rows.reduce(0) { $0 + encodedSize($1) }
                    var firstRetained = 0
                    while firstRetained < rows.count
                        && (rows.count - firstRetained > maxMessages || bytes > maxArchiveBytes)
                    {
                        bytes -= encodedSize(rows[firstRetained])
                        firstRetained += 1
                    }
                    if firstRetained > 0 { rows = Array(rows.dropFirst(firstRetained)) }
                    all[guild] = rows
                    return all
                }
            } catch {
                await logger.log("ERROR", "Recovery message snapshot was not persisted: " + error.localizedDescription)
            }
        }

        func savedMessage(_ guild: String, _ channel: String, _ message: String) async -> Message? {
            let rows = await store.get("recovery.messages", as: [String: [Message]].self) ?? [:]
            return rows[guild]?.first(where: { $0.id == message && $0.channelID == channel })
        }

        func deletedMessage(_ guild: String, _ channel: String, _ message: String) async -> Message? {
            let rows = await store.get("recovery.messages", as: [String: [Message]].self) ?? [:]
            guard let found = rows[guild]?.first(where: { $0.id == message && $0.channelID == channel }) else { return nil }
            await logger.log("INFO", "Recovery retained deleted message " + message + " from guild " + guild)
            return found
        }
}
