{
  lib,
  secrets,
  myvars,
  ...
}:
let
  inherit (lib) mkOption types;
in
rec {
  deployNode = import ./deployNode.nix;
  deployRsLib = import ./deployRsLib.nix;
  macosSystem = import ./macosSystem.nix;
  nixosSystem = import ./nixosSystem.nix;
  mkTasksLib = import ./tasks.nix;
  mkHomeManagerModule = import ./homeManagerModule.nix;
  mkHomeConfigurations = import ./homeConfigurations.nix { inherit lib myvars; };
  relativeToRoot = lib.path.append ../.;

  mkBoolOpt =
    default: description:
    mkOption {
      inherit default description;
      type = types.bool;
    };

  mkLaunchCommand =
    {
      name,
      commandFile,
      domain ? "user",
      config ? { },
    }:
    {
      enable = true;
      inherit domain;
      config = {
        Label = "space.ooooo.${name}";
        ProgramArguments = [ "${commandFile}" ];
        RunAtLoad = true;
        StandardOutPath = "/tmp/nix-hm-logs/${name}.log";
        StandardErrorPath = "/tmp/nix-hm-logs/${name}.err.log";
      }
      // config;
    };

  loadTasks =
    path: args:
    if !builtins.pathExists path then
      { }
    else
      builtins.listToAttrs (
        map
          (
            f:
            let
              raw = import (path + "/${f}");
              val = if builtins.isFunction raw then raw args else raw;
            in
            {
              name = lib.strings.removeSuffix ".nix" f;
              value = val;
            }
          )
          (
            lib.filter (f: f != "default.nix" && lib.strings.hasSuffix ".nix" f) (
              builtins.attrNames (builtins.readDir path)
            )
          )
      );

  calcUniformSchedule =
    {
      hostname,
      startHour,
      endHour,
      hostnames ? null,
    }:
    let
      allHostnames =
        if hostnames != null then
          hostnames
        else
          builtins.attrNames (lib.filterAttrs (_: h: h.type != "openwrt") (import ../hosts));
      hostnameHashes = map (h: {
        name = h;
        hash = builtins.hashString "sha1" h;
      }) allHostnames;
      sortedByHash = lib.sort (a: b: a.hash < b.hash) hostnameHashes;
      hostnameIndex = lib.lists.findFirstIndex (x: x == hostname) null (map (x: x.name) sortedByHash);
      totalHours = endHour - startHour;

      baseHour =
        if hostnameIndex != null then startHour + lib.mod hostnameIndex totalHours else startHour;

      baseMinute = lib.mod (builtins.stringLength hostname * 13) 60;
    in
    {
      hour = baseHour;
      minute = baseMinute;
    };

  mkDefaultSecret =
    overrides@{ ... }:
    {
      sopsFile = secrets + "/sops/secrets/${myvars.username}/default.yaml";
      mode = "0500";
    }
    // overrides;

  mkSopsSecrets =
    secretsList:
    lib.listToAttrs (
      map (name: {
        inherit name;
        value = mkDefaultSecret { };
      }) secretsList
    );
  discoverSkills =
    dir:
    {
      exclude ? [ ],
      frontmatter ? { },
    }:
    let
      collect =
        rel:
        let
          entries = builtins.readDir (if rel == "" then dir else dir + "/${rel}");
          child = name: if rel == "" then name else "${rel}/${name}";
        in
        if entries ? "SKILL.md" then
          [ rel ]
        else
          lib.concatMap (name: collect (child name)) (
            builtins.attrNames (lib.filterAttrs (_: type: type == "directory") entries)
          );
      found = map (rel: {
        name = lib.replaceStrings [ "/" ] [ "--" ] rel;
        source = dir + "/${rel}";
      }) (collect "");
      names = map (skill: skill.name) found;
      unknown = builtins.filter (name: !(builtins.elem name names)) (
        exclude ++ builtins.attrNames frontmatter
      );
    in
    assert lib.assertMsg (
      unknown == [ ]
    ) "discoverSkills ${toString dir}：exclude/frontmatter 里的 skill 不存在：${toString unknown}";
    map (skill: skill // { frontmatter = frontmatter.${skill.name} or { }; }) (
      builtins.filter (skill: !(builtins.elem skill.name exclude)) found
    );
  # EXTERNAL: 参数须为仓库内存在的 Nix 路径值（通常写 ./文件）；liveEdit 校验求值输入树存在性但软链指向 ~/nix-config 工作树，输入快照与工作树不同步时仍可能悬空
  mkConfigLink =
    config: path:
    let
      root = toString (relativeToRoot ".");
      abs = toString path;
      relPath = lib.removePrefix "${root}/" abs;
    in
    assert lib.assertMsg (lib.hasPrefix "${root}/" abs) "mkConfigLink: ${abs} 不在仓库内";
    assert lib.assertMsg (builtins.pathExists path) "mkConfigLink: ${relPath} 不存在";
    if config.shelken.dotfiles.liveEdit or false then
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/${relPath}"
    else
      "${path}";

  mkConfigFile = config: path: {
    source = mkConfigLink config path;
    force = true;
  };
}
