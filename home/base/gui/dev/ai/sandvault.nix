{
  config,
  lib,
  pkgs,
  ...
}:
let
  aiCfg = config.shelken.dev.ai;
  piCfg = config.shelken.dev.ai.pi;
  home = config.home.homeDirectory;
  user = config.home.username;
  workspace = "/Users/Shared/sv-${user}";
  target = "${workspace}/user";
  agentTarget = "${target}/.pi/agent";
  miseTarget = "${workspace}/mise";

  miseInstallNames = map (tool: lib.replaceStrings [ ":" "/" ] [ "-" "-" ] tool) (
    builtins.attrNames config.programs.mise.globalConfig.tools
  );

  sandboxSettings = builtins.toJSON (
    piCfg.baseSettings
    // {
      packages = piCfg.remotePackages;
    }
  );

  sandboxSettingsFile = pkgs.writeText "sandvault-pi-settings.json" sandboxSettings;

  secretFiles = {
    CONTEXT7_API_KEY = config.sops.secrets."context7/api-key".path;
    DEEPSEEK_API_KEY = config.sops.secrets."deepseek/api-key".path;
    DASHSCOPE_API_KEY = config.sops.secrets."dashscope/api-key".path;
    GROQ_API_KEY = config.sops.secrets."groq/api-key".path;
    MODELSCOPE_API_KEY = config.sops.secrets."modelscope/api-key".path;
  };

  specificSecrets = [ "OPENCODE_API_KEY" ];

  syncSecret = variable: source: ''
    if [[ -r ${lib.escapeShellArg source} ]]; then
      printf 'export ${variable}=%q\n' "$(<${lib.escapeShellArg source})" >> "$zshenv"
    fi
  '';

  syncSpecificSecret = variable: ''
    if [[ -r ${lib.escapeShellArg "${home}/.specific.zsh"} ]]; then
      value="$(
        ${pkgs.coreutils}/bin/env -i \
          HOME=${lib.escapeShellArg home} \
          PATH=/usr/bin:/bin \
          ${pkgs.zsh}/bin/zsh -fc \
            'source "$1" >/dev/null || exit 0; print -rn -- ''${(P)2}' \
            zsh \
            ${lib.escapeShellArg "${home}/.specific.zsh"} \
            ${lib.escapeShellArg variable}
      )"
      if [[ -n "$value" ]]; then
        printf 'export ${variable}=%q\n' "$value" >> "$zshenv"
      else
        printf 'SandVault note: %s is empty or not exported in ~/.specific.zsh\n' ${lib.escapeShellArg variable} >&2
      fi
    else
      printf 'SandVault note: ~/.specific.zsh not found; skipping %s\n' ${lib.escapeShellArg variable} >&2
    fi
  '';

  syncMiseTool = name: ''
    ${pkgs.rsync}/bin/rsync -a --no-perms --no-times --delete \
      ${lib.escapeShellArg "${home}/.local/share/mise/installs/${name}/"} \
      "$mise_target/installs/${name}/"
  '';
in
{
  config = lib.mkIf (aiCfg.enable && pkgs.stdenv.isDarwin) {
    home.activation.syncSandvaultPi = lib.hm.dag.entryAfter [ "writePiSubagentConfig" ] ''
            target=${lib.escapeShellArg target}
            agent_target=${lib.escapeShellArg agentTarget}
            mise_target=${lib.escapeShellArg miseTarget}
            zshenv="$target/.zshenv"

            mkdir -p "$agent_target" "$target/.agents" "$target/.config/ponytail" "$mise_target/config/mise" "$target/bin"

            ln -sfn ${lib.escapeShellArg config.home.path} "${workspace}/nix-profile"

            ${pkgs.rsync}/bin/rsync -aL --delete \
              --exclude=.git \
              --exclude=settings.json \
              --exclude=sandbox-extensions/ \
              --exclude=npm/ \
              --exclude=git/ \
              --exclude=sessions/ \
              --exclude=logs/ \
              --exclude=cache/ \
              --exclude=fff/ \
              --exclude=tmp/ \
              --exclude=intercom/ \
              ${lib.escapeShellArg "${home}/.pi/agent/"} \
              "$agent_target/"
            install -Dm644 ${lib.escapeShellArg sandboxSettingsFile} "$agent_target/settings.json"
            install -Dm644 ${lib.escapeShellArg "${home}/nix-config/home/base/gui/dev/ai/_agents.md"} "$agent_target/AGENTS.md"

            ${pkgs.rsync}/bin/rsync -aL --delete \
              ${lib.escapeShellArg "${home}/.agents/skills/"} \
              "$target/.agents/skills/"
            install -Dm644 ${lib.escapeShellArg "${home}/.config/ponytail/config.json"} "$target/.config/ponytail/config.json"

            mkdir -p "$mise_target/installs"
            managed_tools="$(mktemp "$mise_target/.managed-tools.XXXXXX")"
            printf '%s\n' ${
              lib.concatMapStringsSep " " lib.escapeShellArg miseInstallNames
            } > "$managed_tools"
            for install in "$mise_target"/installs/*; do
              [[ -e "$install" || -L "$install" ]] || continue
              tool="$(basename "$install")"
              grep -Fxq "$tool" "$managed_tools" || rm -rf "$install"
            done
            ${lib.concatMapStringsSep "\n" syncMiseTool miseInstallNames}
            mv "$managed_tools" "$mise_target/.managed-tools"
            install -Dm644 ${lib.escapeShellArg "${home}/.config/mise/config.toml"} "$mise_target/config/mise/config.toml"

            cat > "$target/bin/pi" <<'EOF'
      #!/bin/bash
      set -Eeuo pipefail

      # Locate the actual pi binary inside the sandbox
      PI_BIN=""
      if [[ -x "$HOME/.local/bin/pi" ]]; then
          PI_BIN="$HOME/.local/bin/pi"
      elif [[ -x "/opt/homebrew/bin/pi" ]]; then
          PI_BIN="/opt/homebrew/bin/pi"
      else
          PI_BIN="$(which -a pi 2>/dev/null | grep -v "/bin/pi" | head -n 1 || true)"
      fi

      if [[ -z "$PI_BIN" || ! -x "$PI_BIN" ]]; then
          echo >&2 "ERROR: pi binary not found in sandbox (.local/bin/pi or homebrew)"
          exit 1
      fi

      # Package management subcommands and help/version flags execute directly without --approve
      is_subcommand=false
      for arg in "$@"; do
          case "$arg" in
              list|install|remove|uninstall|update|config|auth|--help|-h|--version|-v)
                  is_subcommand=true
                  break
                  ;;
          esac
      done

      if [[ "$is_subcommand" == "true" ]]; then
          exec "$PI_BIN" "$@"
      else
          exec "$PI_BIN" --approve "$@"
      fi
      EOF
            chmod 755 "$target/bin/pi"

            install -Dm640 /dev/null "$zshenv"
            printf 'export PI_CODING_AGENT_DIR=%q\n' "$agent_target" >> "$zshenv"
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList syncSecret secretFiles)}
            ${lib.concatMapStringsSep "\n" syncSpecificSecret specificSecrets}

            cat > "$target/.zprofile" <<EOF
      export MISE_DATA_DIR="\$SHARED_WORKSPACE/mise"
      export MISE_CONFIG_FILE="\$SHARED_WORKSPACE/mise/config/mise/config.toml"
      export PATH="\$SHARED_WORKSPACE/user/bin:\$SHARED_WORKSPACE/nix-profile/bin:/run/current-system/sw/bin:\$SHARED_WORKSPACE/mise/installs/bun/1.3.14/bin:/opt/homebrew/bin:/opt/homebrew/sbin:\$PATH"
      EOF

            cat > "$target/.zshrc" <<EOF
      export MISE_DATA_DIR="\$SHARED_WORKSPACE/mise"
      export MISE_CONFIG_FILE="\$SHARED_WORKSPACE/mise/config/mise/config.toml"
      export PATH="\$SHARED_WORKSPACE/user/bin:\$SHARED_WORKSPACE/nix-profile/bin:/run/current-system/sw/bin:\$PATH"
      if [[ -f "\$SHARED_WORKSPACE/mise/config/mise/config.toml" ]]; then
        eval "\$(mise activate zsh)"
      fi
      EOF

            chmod -R g+rX "$target/.agents" "$target/.config/ponytail" "$agent_target/extensions"
            for file in "$agent_target/auth.json" "$agent_target/models.json" "$agent_target/models-store.json" "$zshenv" "$target/.zprofile" "$target/.zshrc"; do
              [[ -e "$file" ]] && chmod 640 "$file"
            done
    '';
  };
}
