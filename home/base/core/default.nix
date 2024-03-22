{mylib, ...}: {
  imports = (mylib.scanPaths ./.)
  ++ [
    ../../apps/yazi
  ];
}
