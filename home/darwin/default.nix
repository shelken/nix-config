{ mylib, ... }:
{
  imports = mylib.scanPaths ./.;

  xdg.enable = true;
}
