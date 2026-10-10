{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkAfter mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.homelab.omlx;
in
{
  options.shelken.homelab.omlx.enable = mkBoolOpt false "Whether or not to enable.";

  config = mkIf cfg.enable {
    homebrew.taps = [
      {
        name = "jundot/omlx";
        trusted = true;
      }
    ];

    homebrew.brews = [
      # STT 推理服务(Qwen3-ASR),home-ops 集群侧经 stt-voice Service 对接
      "jundot/omlx/omlx"
    ];

    # pin 挂 postActivation:主激活脚本只拼固定名单,自定义命名的脚本段不会被执行;
    # postActivation 在序列上位于 homebrew bundle 之后,types.lines 经 mkAfter 追加到既有内容尾部
    # activation 以 root 运行,按 homebrew 模块同款方式降到 brew 用户执行,幂等
    system.activationScripts.postActivation.text = mkAfter ''
      sudo --user=${config.homebrew.user} --set-home env \
        PATH=/opt/homebrew/bin:/usr/bin:/bin \
        /opt/homebrew/bin/brew pin jundot/omlx/omlx || true
    '';
  };
}
