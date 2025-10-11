{
  lib,
  rime-main,
  pkgs,
  ...
}:
let
  # squirrel is only for darwin
  rimeDir = "Library/Rime";
  rime-config = pkgs.dot-squirrel;
  custom_file_list = builtins.attrNames (builtins.readDir (rime-config + "/custom"));
  custom_attrs = lib.attrsets.mergeAttrsList (
    builtins.map (custom_file: {
      "${rimeDir}/${custom_file}" = {
        source = "${rime-config}/custom/${custom_file}";
        force = true;
      };
    }) custom_file_list
  );
in
{
  home.file = {
    "${rimeDir}" = {
      source = rime-main;
      recursive = true;
      force = true;
    };
  }
  // custom_attrs;
}
