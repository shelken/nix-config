{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [
    config.flake.modules.homeManager.gh
    config.flake.modules.homeManager.gh-dash
  ];

  flake.modules.homeManager.gh =
    { pkgs, myvars, ... }:
    {
      shelken.dev.tools.gh.package =
        pkgs:
        import ./_package.nix {
          inherit pkgs;
          owner = myvars.username;
        };
      home.packages =
        (with pkgs; [
          gh-markdown-preview
          gh-stack
        ])
        ++ [
          (pkgs.writeShellApplication {
            name = "gh-fetch";
            runtimeInputs = with pkgs; [
              gh
              curl
              git
              coreutils
            ];
            text = builtins.readFile ./gh-fetch.sh;
          })
        ];
      programs.git.settings.credential = {
        # 加空白是先清除system定义的osxkeychain
        "https://github.com" = {
          helper = [
            ""
            "!${pkgs.gh}/bin/gh auth git-credential"
          ];
        };
        "https://gist.github.com" = {
          helper = [
            ""
            "!${pkgs.gh}/bin/gh auth git-credential"
          ];
        };
        "https://mirrors.tuna.tsinghua.edu.cn" = {
          helper = [
            ""
            "!${pkgs.gh}/bin/gh auth git-credential"
          ];
        };
      };
    };

  flake.modules.homeManager.gh-dash = {
    programs.gh-dash.enable = true;
    programs.gh-dash.settings = {
      prSections = [
        {
          title = "Pull Requests";
          filters = "is:open";
        }
        {
          title = "My Pull Requests";
          filters = "is:open author:@me";
        }
        {
          title = "Needs My Review";
          filters = "is:open review-requested:@me";
        }
        {
          title = "Involved";
          filters = "is:open involves:@me -author:@me";
        }
      ];
      keybindings.universal = [
        {
          key = "pgup";
          builtin = "pageUp";
        }
        {
          key = "pgdown";
          builtin = "pageDown";
        }
      ];
    };
  };
}
