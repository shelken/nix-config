{mylib, ...}: {
  imports =
    (mylib.scanPaths ./.)
    ++ [
    ];
}
