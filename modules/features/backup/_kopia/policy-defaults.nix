# kopia 本机备份策略默认值：目标固定为 <user>@<host>，用户级额外忽略模式见 ../_options.nix
{
  compression = "zstd-fastest";
  ignores = [
    "*.tmp"
    ".direnv"
    ".venv"
    ".vitepress"
    "*.temp"
    "*.log"
    "*.cache"
    "node_modules"
    "dist"
    "*.DS_Store"
    ".DS_Store?"
    "._*"
    ".Spotlight-V100"
    ".Trashes"
    "Thumbs.db"
    ".scratch"
    ".playwright-cli"
    ".build"
    "target"
    "kaiyuan"
  ];
  retention = {
    latest = 48;
    daily = 30;
    weekly = 12;
    monthly = 12;
  };
}
