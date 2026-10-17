{
  lib,
  pkgs,
  #secrets,
  ...
}:
{
  # string -> string
  # this capitalizes the first letter in a string,
  # which is sometimes needed in order to format
  # the names of themes correctly
  mkUpper =
    str: with builtins; (lib.toUpper (substring 0 1 str)) + (substring 1 (stringLength str) str);
}
