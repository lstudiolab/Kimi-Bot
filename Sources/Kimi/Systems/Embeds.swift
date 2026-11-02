import Foundation
struct EmbedDefinition:Codable,Sendable {
    struct Field:Codable,Sendable {let name:String;let value:String;let inline:Bool}
    var title:String;var description:String;var color:Int;var fields:[Field]
    func validate()->[String] {
        var errors:[String]=[]
        if title.count>256{errors.append("Title exceeds 256 characters.")}
        if description.count>4096{errors.append("Description exceeds 4096 characters.")}
        if fields.count>25{errors.append("Discord allows at most 25 fields.")}
        if fields.contains(where:{$0.name.isEmpty || $0.value.isEmpty || $0.name.count>256 || $0.value.count>1024}){errors.append("Invalid field length.")}
        return errors
    }
}
