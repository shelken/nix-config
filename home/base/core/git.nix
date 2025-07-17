{
  myvars,
  pkgs,
  lib,
  ...
}: let
  catppuccin-delta-theme-path = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "delta";
    rev = "e9e21cff";
    hash = "sha256-04po0A7bVMsmYdJcKL6oL39RlMLij1lRKvWl5AUXJ7Q=";
  };
  flavor = lib.strings.toLower myvars.catppuccin_flavor;
in {
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
      {path = "${catppuccin-delta-theme-path}/catppuccin.gitconfig";}
    ];
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      log.date = "format:'%Y-%m-%d %H:%M:%S'";
      push = {
        autoSetupRemote = true;
        default = "current";
        followTags = true;
      };
      rebase = {
        autoStash = true;
      };
      core = {
        whitespace = "error";
        autocrlf = "input";
      };
      status = {
        short = true;
        showStash = true;
      };
      submodule = {
        fetchJobs = 16;
      };
      advice = {
        statusHints = false;
      };
      blame = {
        coloring = "highlightRecent";
        date = "relative";
      };
      diff = {
        renames = "copies";
        interHunkContext = 10;
      };
      url = {
        "git@github.com:".insteadOf = "gh:";
      };
      delta = {
        navigate = true;
        features = "catppuccin-${flavor}";
        side-by-side = true;
        hyperlinks = true;
      };
    };
    aliases = {
      # git change-commits GIT_COMMITTER_NAME "old name" "new name"
      change-commits = "!f() { VAR=$1; OLD=$2; NEW=$3; shift 3; git filter-branch --env-filter \"if [[ \\\"$`echo $VAR`\\\" = '$OLD' ]]; then export $VAR='$NEW'; fi\" $@; }; f ";
      # search config
      cs = "config --get-regexp";
    };
    # 差异对比增强
    difftastic.enable = false; # https://github.com/Wilfred/difftastic.
    delta.enable = false;
  };

  home.packages = with pkgs; [
    onefetch # 显式当前git项目的详细信息
    git-cliff #
    git-filter-repo # 清除git大文件，修改历史
  ];

  home.sessionVariables = {
    # COMOJI_EMOJI_FORMAT = "true";
  };

  home.shellAliases = {
  };
}
