// 把 Nix 声明的自定义命令合并进 Tinycast 的 UserDefaults。
// 命令内容不在 settings.json 里，只能由 App 之外的写入者补进去：同 id 的记录以
// Nix 声明为准，其余记录原样保留，所以用户手建的命令不会被清掉。
import Foundation

guard let defaults = UserDefaults(suiteName: "com.tinycast.app") else { exit(1) }

let managedJSON = CommandLine.arguments[1]
guard let managedData = managedJSON.data(using: .utf8),
      let managedList = try? JSONSerialization.jsonObject(with: managedData) as? [[String: Any]]
else { exit(1) }

let managedIDs = Set(managedList.compactMap { $0["id"] as? String })

var currentList: [[String: Any]] = []
if let existingData = defaults.data(forKey: "customCommands"),
   let decoded = try? JSONSerialization.jsonObject(with: existingData) as? [[String: Any]] {
    currentList = decoded.filter {
        guard let id = $0["id"] as? String else { return true }
        return !managedIDs.contains(id)
    }
}

currentList.append(contentsOf: managedList)

guard let mergedData = try? JSONSerialization.data(withJSONObject: currentList) else { exit(1) }
if defaults.data(forKey: "customCommands") != mergedData {
    defaults.set(mergedData, forKey: "customCommands")
}
