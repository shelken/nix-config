{mylib, ...}: {
  imports =
    (mylib.scanPaths ./.)
    ++ [../apps];
}
