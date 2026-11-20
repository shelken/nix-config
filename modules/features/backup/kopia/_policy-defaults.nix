{
  compression = "zstd-fastest";
  ignores = [
    "*.tmp"
    ".direnv"
    ".venv"
    "build"
    ".build"
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
