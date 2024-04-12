{
  myvars,
  pkgs,
  ...
}: {
  imports = [
    ../../apps/lazygit
  ];
  programs.git = {
    enable = true;
    userName = myvars.username;
    userEmail = myvars.useremail;
    ignores = [
      ".DS_Store"
    ];
    attributes = [
    ];
    includes = [
      {
        # use different email & name for work
        path = "~/work/.gitconfig";
        # condition = "gitdir:~/work/";
      }
    ];
    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
    };
    aliases = {
      # common aliases
      # br = "branch";
      # co = "checkout";
      # st = "status";
      ls = "log --pretty=format:\"%C(yellow)%h%Cred%d\\\\ %Creset%s%Cblue\\\\ [%cn]\" --decorate";
      ll = "log --pretty=format:\"%C(yellow)%h%Cred%d\\\\ %Creset%s%Cblue\\\\ [%cn]\" --decorate --numstat";
      # cm = "commit -m"; # commit via `git cm <message>`
      # ca = "commit -am"; # commit all changes via `git ca <message>`
      # dc = "diff --cached";
      #
      # amend = "commit --amend -m"; # amend commit message via `git amend <message>`
      # unstage = "reset HEAD --"; # unstage file via `git unstage <file>`
      # merged = "branch --merged"; # list merged(into HEAD) branches via `git merged`
      # unmerged = "branch --no-merged"; # list unmerged(into HEAD) branches via `git unmerged`
      # nonexist = "remote prune origin --dry-run"; # list non-exist(remote) branches via `git nonexist`
      #
      # # delete merged branches except master & dev & staging
      # #  `!` indicates it's a shell script, not a git subcommand
      # delmerged = ''! git branch --merged | egrep -v "(^\*|main|master|dev|staging)" | xargs git branch -d'';
      # # delete non-exist(remote) branches
      # delnonexist = "remote prune origin";
      #
      # # aliases for submodule
      # update = "submodule update --init --recursive";
      # foreach = "submodule foreach";
    };
    difftastic.enable = true; # https://github.com/Wilfred/difftastic.
  };

  home.packages = with pkgs; [
    onefetch
    git-cliff
    comoji
  ];

  home.sessionVariables = {
    COMOJI_EMOJI_FORMAT = "true";
  };

  home.shellAliases = {
    comojit = "lazygit && comoji commit && lazygit";
  };
}
