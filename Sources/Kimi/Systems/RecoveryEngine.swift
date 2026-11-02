import Foundation

actor RecoveryEngine {
 struct Snapshot:Codable,Sendable,Identifiable {let id:String;let guildID:String;let createdAt:Date;let payload:[String:Data]}
 private let store:PersistentStore
 init(store:PersistentStore){self.store=store}
 func create(guildID:String,sections:[String:Data])async throws->Snapshot{
  let snapshot=Snapshot(id:UUID().uuidString,guildID:guildID,createdAt:Date(),payload:sections)
  var all=await store.get("recovery.snapshots",as:[Snapshot].self) ?? []
  all.append(snapshot);all=Array(all.suffix(50))
  try await store.set(all,key:"recovery.snapshots");return snapshot
 }
 func snapshots(guildID:String)async->[Snapshot]{(await store.get("recovery.snapshots",as:[Snapshot].self) ?? []).filter{$0.guildID==guildID}}
}
