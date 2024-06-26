{mylib, ...}: {
  imports =
    (mylib.scanPaths ./.)
    ++ [
      ../base/server
    ];
}
