{ pkgs, ... }:
{
  script = pkgs.writeShellScriptBin "idea" ''
    idea_function() {
      local path="$1"
      if [ -z "$path" ]; then
        path="."
      fi
      open -a '/Applications/IntelliJ IDEA.app/Contents/MacOS/idea' "$path"
    }
    idea_function "$@"
  '';
}
