import Foundation

extension VerificationService {
        func verify(guild: String, userID: String, username: String, applicationID: String, interactionToken: String) async
        {
            let records = VerificationRecords(store: store)
            let prior = await records.record(guildID: guild, userID: userID)
            if prior.verifiedAt != nil {
                try? await rest.editKimiInteraction(applicationID, interactionToken, "You have already been verified.")
                return
            }
            if prior.reviewMessageID != nil {
                try? await rest.editKimiInteraction(
                    applicationID, interactionToken, "Your verification is already awaiting server-owner review.")
                return
            }
            let value = await settings(guild)
            if let required = value.requiredRoleID {
                let member =
                    (try? await rest.call("GET", "guilds/" + guild + "/members/" + userID)) as? [String: Any] ?? [:]
                let memberRoles = Set(member["roles"] as? [String] ?? [])
                guard memberRoles.contains(required) else {
                    try? await rest.editKimiInteraction(
                        applicationID, interactionToken, "You need the required server role before verification.")
                    return
                }
            }
            do {
                _ = try await records.attempt(guildID: guild, userID: userID)
            } catch {
                await logger.log("ERROR", "Verification attempt could not be persisted: " + error.localizedDescription)
                try? await rest.editKimiInteraction(
                    applicationID, interactionToken, "Verification is temporarily unavailable. Please try again later.")
                return
            }
            let record = await records.record(guildID: guild, userID: userID)
            let snowflake = Int64(userID) ?? 0
            let created = Date(timeIntervalSince1970: Double((snowflake >> 22) + 1_420_070_400_000) / 1000)
            let profile: [String: Any]?
            do {
                profile = try await rest.call("GET", "users/" + userID) as? [String: Any]
            } catch {
                profile = nil
                await logger.log(
                    "WARN",
                    "Could not retrieve the verification profile for " + userID
                        + "; avatar presence was not used as a risk signal: " + error.localizedDescription)
            }
            // A failed profile request is not evidence of a default avatar.
            let defaultAvatar = profile.map { ($0["avatar"] as? String) == nil } ?? false
            let result = VerificationEngine().evaluate(
                createdAt: created, defaultAvatar: defaultAvatar, suspiciousBehavior: record.failures > 0,
                attempts: record.attempts, minimumAgeDays: value.minimumAgeDays)
            let age = max(0, Int(Date().timeIntervalSince(created) / 86400))
            if result.decision != .approve {
                if result.decision == .reject {
                    try? await records.markFailed(
                        guildID: guild, userID: userID, reason: result.reasons.joined(separator: "; "))
                    do {
                        _ = try await rest.call("DELETE", "guilds/" + guild + "/members/" + userID)
                        try? await rest.editKimiInteraction(
                            applicationID, interactionToken,
                            "Verification score: " + String(result.score)
                                + "/100. The account did not meet the minimum safety score and was removed.")
                        await logger.log(
                            "WARN",
                            "Verification automatically removed member " + userID + " from guild " + guild + "; score "
                                + String(result.score))
                        return
                    } catch {
                        await logger.log("ERROR", "Automatic verification removal failed: " + error.localizedDescription)
                    }
                }
                var queued = false
                if let review = value.reviewChannelID {
                    let details =
                        result.reasons.isEmpty ? "No additional risk signals." : result.reasons.joined(separator: "; ")
                    let body =
                        "Verification review required for <@\(userID)>. Score: " + String(result.score)
                        + "/100. Account age: " + String(age) + " days. " + details
                    let components =
                        [
                            [
                                "type": 1,
                                "components": [
                                    ["type": 2, "style": 2, "custom_id": "verify:approve:" + userID],
                                    ["type": 2, "style": 2, "custom_id": "verify:reject:" + userID],
                                ],
                            ]
                        ] as [[String: Any]]
                    do {
                        let posted = try await rest.call(
                            "POST", "channels/\(review)/messages",
                            body: KimiUI.panel(title: "Verification review", description: body, components: components))
                        guard let messageID = (posted as? [String: Any])?["id"] as? String, !messageID.isEmpty else {
                            throw KimiError.invalidResponse
                        }
                        do {
                            try await records.setReviewMessage(guildID: guild, userID: userID, messageID: messageID)
                        } catch {
                            _ = try? await rest.call("DELETE", "channels/\(review)/messages/\(messageID)")
                            throw error
                        }
                        queued = true
                    } catch {
                        await logger.log("ERROR", "Verification review could not be queued: " + error.localizedDescription)
                    }
                }
                let response =
                    queued
                    ? "Verification score: " + String(result.score) + "/100. Your request was sent for manual review."
                    : "Verification score: " + String(result.score)
                        + "/100. Manual review is required, but the review channel is not configured."
                try? await rest.editKimiInteraction(applicationID, interactionToken, response)
                return
            }
            if let role = value.roleID {
                do {
                    let roles = try await rest.call("GET", "guilds/\(guild)/roles") as? [[String: Any]] ?? []
                    let bot = try await rest.call("GET", "guilds/\(guild)/members/@me") as? [String: Any] ?? [:]
                    let botIDs = Set(bot["roles"] as? [String] ?? [])
                    let highest =
                        roles.filter { botIDs.contains($0["id"] as? String ?? "") }.map { $0["position"] as? Int ?? 0 }
                        .max() ?? 0
                    let canManage = roles.contains {
                        botIDs.contains($0["id"] as? String ?? "")
                            && ((UInt64($0["permissions"] as? String ?? "") ?? 0) & ((1 << 28) | (1 << 3)) != 0)
                    }
                    guard let target = roles.first(where: { ($0["id"] as? String) == role }) else {
                        throw KimiError.configuration("The verified role no longer exists.")
                    }
                    let permissions = UInt64(target["permissions"] as? String ?? "") ?? 0
                    guard canManage,
                        SecurityPolicy.isSafeRole(
                            roleID: role, guildID: guild, managed: target["managed"] as? Bool ?? false,
                            permissions: permissions), (target["position"] as? Int ?? 0) < highest
                    else {
                        throw KimiError.configuration("The verified role is unsafe, managed, or above Kimi's highest role.")
                    }
                    _ = try await rest.call("PUT", "guilds/\(guild)/members/\(userID)/roles/\(role)")
                } catch {
                    try? await rest.editKimiInteraction(
                        applicationID, interactionToken,
                        "Verification could not assign the configured role: " + error.localizedDescription)
                    return
                }
            }
            do {
                try await VerificationRecords(store: store).markVerified(guildID: guild, userID: userID)
            } catch {
                await logger.log("ERROR", "Verified role was assigned but the verification record could not be saved: " + error.localizedDescription)
                try? await rest.editKimiInteraction(
                    applicationID, interactionToken,
                    "The role was assigned, but verification could not be finalized because its record could not be saved. Contact the server owner.")
                return
            }
            try? await rest.editKimiInteraction(
                applicationID, interactionToken, "Verification complete. You now have access to the server.")
        }
}
