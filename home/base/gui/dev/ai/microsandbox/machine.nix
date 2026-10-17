# 机器覆盖层: 指向该机器的原生 msb YAML 规范，并声明依赖的 Linux 工具链
# 新机器 = 新增 sb-<name>.yaml 与此处的对应 attr
{
  default = {
    conf = ./sb-default.yaml;

    tools = linuxPkgs: with linuxPkgs; [
      bashInteractive
      coreutils
      ripgrep
      fd
      git
      gh
      jq
      curl
      mise
      cacert
      bun
    ];
  };
}
