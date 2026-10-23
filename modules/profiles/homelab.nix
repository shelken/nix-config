# homelab：附加角色，给日常机器叠加服务器职责，与主角色并列导入：
#   imports = with self.modules.darwin; [ gui homelab ];
# 只放服务器职责的功能，不导入主角色链，否则主角色会被导入两次。
# 功能在自己的文件里声明加入（见 features/homelab/lima.nix）；
# 候选：lm-studio、ollama-app、osaurus
{
  flake.modules.darwin.homelab = { };
}
