{ mylib, ... }@args:
(map (path: (import path args)) (mylib.scanPaths ./.))
++ [
  # (import ./maven.nix args)
]
