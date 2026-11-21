{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.git ];
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.git-tools ];

  flake.modules.homeManager.git =
    {
      config,
      lib,
      myvars,
      pkgs,
      ...
    }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "git-scan";
          runtimeInputs = with pkgs; [
            git
            findutils
            coreutils
          ];
          text = builtins.readFile ./git-scan.sh;
        })
      ];
      home.activation.removeExistingGitconfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        rm -f ${config.home.homeDirectory}/.gitconfig
      '';

      programs.git = {
        enable = true;
        ignores = [
          ".DS_Store"
          ".idea"
          ".papercuts.jsonl"
          ".pi/notes/"
        ];
        attributes = [
        ];
        includes = [
          {
            path = "~/work/.gitconfig";
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
          alias = {
            change-commits = "!f() { VAR=$1; OLD=$2; NEW=$3; shift 3; git filter-branch --env-filter \"if [[ \\\"$`echo $VAR`\\\" = '$OLD' ]]; then export $VAR='$NEW'; fi\" $@; }; f ";
            cs = "config --get-regexp";
          };
        };
        signing.format = null;
      };
    };

  flake.modules.homeManager.git-tools =
    { pkgs, ... }:
    {
      programs.git.settings.delta = {
        navigate = true;
        hyperlinks = true;
        dark = true;
      };

      programs.delta = {
        enable = true;
        enableGitIntegration = true;
      };

      programs.zsh.oh-my-zsh.plugins = [ "gitignore" ];

      home.packages = with pkgs; [
        onefetch
        git-cliff
        git-filter-repo
        tig
      ];

      programs.lazygit = {
        enable = true;
        settings = {
          gui = {
            timeFormat = "2006-01-02 15:04";
            shortTimeFormat = "15:04";
          };
          git.diffRenderers = [
            {
              colorArg = "always";
              command = "delta --dark --paging=never";
            }
          ];
        };
      };
    };
}
