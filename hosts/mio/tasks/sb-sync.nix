# sb-sync: 设备侧 sing-box 配置同步（拉通用底模+订阅 → 融合本机 local → 原子产出）
# 产物: ~/.config/sing-box/singbox.json；SFM Local Profile 指向该文件
# sb-sync 二进制由 mise 管理（github:shelken/proxy），经 packages 注入 shim 后
# task 环境即可直接调用；latest 符号链接由 mise 轮换，shim 无需随版本更新
{ pkgs, ... }:
{
  every = 86400; # 每 24h 自动同步（订阅刷新+底模自动更新）
  packages = [ pkgs.mise ];
  script = ''
    if [ "$(id -u)" -eq 0 ]; then
      echo "该任务必须以用户身份运行（凭据在用户目录），请用: task-sb-sync" >&2
      exit 1
    fi
    # mise exec -C 指向 proxy 仓库: .mise.toml 声明了 sing-box(原子写校验用)，
    # 加上 github:shelken/proxy@latest 的 sb-sync 一起进 PATH；
    # 不带 -C 时 mise 只按当前目录解析工具，task 环境(~/)下 sing-box 不可见
    mise exec -C "$HOME/Code/active/proxy" -- sb-sync sync
  '';
}
