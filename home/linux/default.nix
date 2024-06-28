{mylib, ...}: {
  imports =
    (mylib.scanPaths ./.)
    ++ [
      ../base/server

      ../apps/vscode-server
    ];
}
