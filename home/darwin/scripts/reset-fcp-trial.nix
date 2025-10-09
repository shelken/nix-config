{ pkgs, ... }:
let
in
{
  script = pkgs.writeShellScriptBin "reset-fcp-trial" ''
    swift ${pkgs.writeText "script.swift" ''
      // from https://gist.github.com/dannote/17e0396fe2e19c6e60c915838376d267

      import Foundation

      let path = URL(fileURLWithPath: NSString(string: "~/Library/Containers/com.apple.FinalCutTrial/Data/Library/Application Support/.ffuserdata").expandingTildeInPath)
      let data = try! NSData(contentsOf: path) as Data
      let dictionary = try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as! NSDictionary
      let mutableDictionary = dictionary.mutableCopy() as! NSMutableDictionary

      for (key, value) in mutableDictionary {
        if value is NSDate {
          mutableDictionary[key] = Date()
        }
      }

      try! NSKeyedArchiver.archivedData(withRootObject: mutableDictionary, requiringSecureCoding: false).write(to: path)
      print("重置成功")
    ''} "$@"
  '';
}
