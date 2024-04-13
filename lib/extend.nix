{
  lib,
  pkgs,
  ...
}: {
  # a -> path -> a
  # fromJSON but for yaml (and without readFile)
  # a should be the local pkgs attrset
  fromYaml = file: let
    inherit (builtins) fromJSON readFile;

    # convert to json
    json = with pkgs;
      runCommand "converted.json" {} ''
        ${yj}/bin/yj < ${file} > $out
      '';
  in
    fromJSON (readFile json);

  # string -> string
  # this capitalizes the first letter in a string,
  # which is sometimes needed in order to format
  # the names of themes correctly
  mkUpper = str:
    with builtins;
      (lib.toUpper (substring 0 1 str)) + (substring 1 (stringLength str) str);
}
