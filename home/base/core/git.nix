{
  config,
  lib,
  myvars,
  pkgs,
  ...
}:
{
  home.activation.removeExistingGitconfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f ${config.home.homeDirectory}/.gitconfig
  '';

  programs.git = {
    enable = true;
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
    settings = {
      user.email = myvars.useremail;
      user.name = myvars.username;
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
        side-by-side = true;
        hyperlinks = true;
        dark = true;
      };
      alias = {
        # git change-commits GIT_COMMITTER_NAME "old name" "new name"
        change-commits = "!f() { VAR=$1; OLD=$2; NEW=$3; shift 3; git filter-branch --env-filter \"if [[ \\\"$`echo $VAR`\\\" = '$OLD' ]]; then export $VAR='$NEW'; fi\" $@; }; f ";
        # search config
        cs = "config --get-regexp";
      };
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  home.packages = with pkgs; [
    onefetch # 显式当前git项目的详细信息
    git-cliff
    git-filter-repo # 清除git大文件，修改历史
    tig
  ];

  programs.lazygit = {
    enable = true;
    settings = {
      # diff with delta
      gui = {
        timeFormat = "2006-01-02 15:04";
        shortTimeFormat = "15:04";
      };
      git.pagers = [
        {
          colorArg = "always";
          pager = "delta --dark --paging=never";
        }
      ];
    };
  };

  home.sessionVariables = {
    # COMOJI_EMOJI_FORMAT = "true";
  };

  home.shellAliases = {
  };
}
