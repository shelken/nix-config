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
