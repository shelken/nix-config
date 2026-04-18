# kopia policy 默认配置
{ hostname, myvars }:
{
  "${myvars.username}@${hostname}" = {
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
    ];
    retention = {
      latest = 48;
      daily = 30;
      weekly = 12;
      monthly = 12;
    };
  };
}
