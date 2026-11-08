{ lib, myvars }:
systemConfigurations:
# Home 不是第二套配置，只导出系统结果中已经求值的 Home 子配置：
# activationPackage 与系统激活用的是同一个 derivation，供 `nh home build/switch` 读取
lib.mapAttrs (
  _: system:
  let
    hm = system.config.home-manager.users.${myvars.username};

    # 与上游 homeManagerConfiguration 等价的断言/告警检查，避免请求 Home 时静默跳过失败断言
    failed = map (x: x.message) (lib.filter (x: !x.assertion) hm.assertions);
    checkedHome =
      if failed != [ ] then
        throw ''
          Failed assertions:
          ${lib.concatStringsSep "\n" (map (x: "- ${x}") failed)}''
      else
        lib.foldr (warning: result: builtins.trace "warning: ${warning}" result) hm hm.warnings;
  in
  {
    config = checkedHome;
    inherit (checkedHome.home) activationPackage;
  }
) systemConfigurations
