{ myvars, ... }:
{
  users.users."${myvars.username}" = {
    home = "/Users/${myvars.username}";

    # 登录 shell 保持 zsh：nu 不兼容 POSIX，ssh 远程命令、VS Code Remote 等都假设登录 shell 是 POSIX
  };
}
