{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      mylib,
      pkgs,
      ...
    }:
    let
      linkOmp = rel: mylib.mkConfigFile config (./. + "/${rel}");

      ompManifest = builtins.fromJSON (builtins.readFile ./plugins/package.json);
      sandboxExclude = ompManifest.sandboxExclude or [ ];
      unknownExcludes = builtins.filter (n: !(ompManifest.dependencies ? ${n})) sandboxExclude;
      sandboxManifest =
        assert lib.assertMsg (
          unknownExcludes == [ ]
        ) "omp plugins/package.json 的 sandboxExclude 有 dependencies 里不存在的条目: ${toString unknownExcludes}";
        (pkgs.formats.json { }).generate "omp-sandbox-plugin-manifest.json" (
          builtins.removeAttrs ompManifest [ "sandboxExclude" ]
          // {
            dependencies = builtins.removeAttrs ompManifest.dependencies sandboxExclude;
          }
        );

      extensionEntries = builtins.attrNames (
        lib.filterAttrs (
          name: type:
          type == "directory"
          || (type == "regular" && lib.hasSuffix ".ts" name && !lib.hasSuffix ".test.ts" name)
        ) (builtins.readDir ./extensions)
      );
      extensionLinks = lib.listToAttrs (
        map (name: {
          name = ".omp/agent/extensions/${name}";
          value = linkOmp "extensions/${name}";
        }) extensionEntries
      );
    in
    {
      config = {
        shelken.dev.tools.omp.env.MNEMOPI_EMBEDDING_DIM = "3072";
        home.shellAliases.omp = "sec-run omp";

        shelken.dev.sandbox.writableRoots = [ ".omp/agent" ];

        shelken.dev.tools.omp.sandboxFiles = {
          ".omp/agent/plugins-package.json" = sandboxManifest;
        };

        shelken.dev.tools.omp.files = {
          ".omp/agent/config.yml" = linkOmp "config.yml";
          ".omp/agent/keybindings.yml" = linkOmp "keybindings.yml";
          ".omp/agent/permissions.yaml" = linkOmp "permissions.yaml";
          ".omp/agent/models.yml" = linkOmp "models.yml";
          ".omp/agent/context-prune/settings.json" =
            mylib.mkConfigFile config ../pi/configs/context-prune.json;
        }
        // extensionLinks;

        shelken.backup.app.omp = [
          "${config.home.homeDirectory}/.omp/agent/sessions"
        ];
        shelken.sessionArchive.app.omp = [
          "${config.home.homeDirectory}/.omp/agent/sessions"
        ];
      };
    };
}
