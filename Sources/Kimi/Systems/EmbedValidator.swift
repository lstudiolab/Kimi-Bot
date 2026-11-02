import Foundation
struct EmbedValidator {
 struct Field:Sendable {let name:String;let value:String}
 struct Definition:Sendable {let title:String;let description:String;let fields:[Field];let color:Int;let imageURL:String?}
 func validate(_ embed:Definition)->[String]{
  var errors:[String]=[]
  if embed.title.count>256{errors.append("Title exceeds Discord's 256 character limit.")}
  if embed.description.count>4096{errors.append("Description exceeds Discord's 4096 character limit.")}
  if embed.fields.count>25{errors.append("An embed can contain at most 25 fields.")}
  for field in embed.fields where field.name.isEmpty || field.name.count>256 || field.value.isEmpty || field.value.count>1024{errors.append("An embed field has invalid content.")}
  if let value=embed.imageURL,let url=URL(string:value),url.scheme != "https"{errors.append("Image URL must use HTTPS.")}
  return errors
 }
}
