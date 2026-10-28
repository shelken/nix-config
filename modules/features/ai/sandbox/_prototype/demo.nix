# PROTOTYPE：仅查看全系统契约，不创建 VM、不安装工具。
# nix eval --impure --json --expr 'let flake = builtins.getFlake (toString ./.); in (import ./modules/features/ai/sandbox/_prototype/demo.nix { inherit flake; }).summary'
{ flake }:
let
  pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
  spec = import ./spec.nix {
    profile = flake.homeConfigurations.mio.config;
  };
  sandbox = import ./default.nix {
    inherit pkgs spec;
    nixpkgs = flake.inputs.nixpkgs;
  };
in
{
  inherit sandbox;
  inspect = sandbox.runtime.cli;
  summary = {
    question = "整个 sandbox 能否由一份 spec 装配，集中生成配置、guest 环境和宿主运行时？";
    interface = {
      cli = pkgs.lib.getExe sandbox.packages.sb;
      publish = pkgs.lib.getExe sandbox.packages.publish;
      contract = sandbox.runtime.contract;
    };
    inherit (sandbox.runtime) vm policy;
    contexts = sandbox.guest.contexts;
    tooling = sandbox.guest.tools;
    configuration = {
      inherit (sandbox.configBundle) root declaredPaths writableRoots;
    };
    safeDefault = "sb-prototype 默认只打印契约；显式运行命令时仅使用 /tmp/sbp-* 独立 MSB_HOME。";
  };
}
