# PROTOTYPE：配置包和唯一发布入口；保留 live-edit 的运行时解引用。
{
  pkgs,
  lib,
  spec,
  guest,
}:
let
  files = lib.foldl' (acc: tool: acc // tool.files // tool.sandboxFiles) { } (
    builtins.attrValues spec.tools
  );
  declaredPaths = builtins.attrNames files;
  under = root: path: path == root || lib.hasPrefix "${root}/" path;
  validTarget =
    path: lib.hasPrefix ".config/" path || lib.any (root: under root path) spec.writableRoots;

  publish = pkgs.writeShellApplication {
    name = "sandbox-publish-prototype";
    text = ''
      export SANDBOX_CONFIG_DIR=${lib.escapeShellArg spec.paths.published}
      exec ${lib.getExe pkgs.bash} ${guest.publicationSource}
    '';
  };
in
assert lib.assertMsg (lib.all validTarget declaredPaths) "sandbox 文件必须位于声明的可写根中";
{
  inherit publish declaredPaths;
  root = spec.paths.published;
  current = "${spec.paths.published}/current";
  policy = spec.policy;
  writableRoots = spec.writableRoots;
}
