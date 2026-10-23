{ myvars, ... }:
{
  users.users."${myvars.username}" = {
    home = "/Users/${myvars.username}";

    # set user's default shell back to zsh
    #    `chsh -s /bin/zsh`
    # DO NOT change the system's default shell to nushell! it will break some apps!
    # It's better to change only kitty/wezterm's shell to nushell!
  };
}
