{ lib, pkgs }:
{
  # 先用 yj 转成 json 再读入（构建期 IFD）
  readYaml =
    file:
    builtins.fromJSON (
      builtins.readFile (
        pkgs.runCommand "converted.json" { } ''
          ${pkgs.yj}/bin/yj < ${file} > $out
        ''
      )
    );

  # 沙箱内 loopback 指向 VM 自身，模型的 baseUrl 要改成宿主网关。
  # 在 Nix 层改写，YAML 与 JSON 两种模型配置共用同一份逻辑，不依赖 yq/jq。
  rewriteLoopbackBaseUrls =
    gateway: attrs:
    let
      # Nix 正则不支持字符类转义与可选量词作用于转义字符，IPv6 只匹配 ::1 本体
      isLoopback = url: builtins.match "https?://(127[.]0[.]0[.]1|localhost|::1)(.*)" url != null;
      rewrite =
        url:
        let
          m = builtins.match "(https?://)(127[.]0[.]0[.]1|localhost|::1)(.*)" url;
        in
        if isLoopback url then builtins.elemAt m 0 + gateway + builtins.elemAt m 2 else url;
      walk =
        value:
        if builtins.isAttrs value then
          lib.mapAttrs (k: v: if k == "baseUrl" && builtins.isString v then rewrite v else walk v) value
        else if builtins.isList value then
          map walk value
        else
          value;
    in
    walk attrs;
}
