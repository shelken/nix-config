{
  comoji,
  mylib,
  ...
} @ args:
(
  map
  (path: (import path args))
  (mylib.scanPaths ./.)
)
++ [
  # (import ./maven.nix args)
  comoji.overlays.default
]
