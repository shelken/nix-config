# AGENTS.md

## Principles

- Chinese conversation, Chinese comments, Chinese documentation

## Architecture

This is a Nix Flakes-based multi-platform configuration repository that manages macOS (nix-darwin)
and Linux (NixOS).

- **Entry point**: `flake.nix`
- **Modularization**:
  - `modules/base`: cross-platform shared configuration
  - `modules/darwin`: macOS-specific configuration
  - `modules/nixos`: Linux-specific configuration
  - `home/`: Home Manager configuration, split by platform (`darwin`/`linux`)
- **Machine configuration**: `hosts/<hostname>/default.nix`
- **Variables and libraries**:
  - `vars/`: global variables (username, email, etc.)
  - `lib/`: custom functions (`mylib.scanPaths`, `mylib.relativeToRoot`, etc.)

## Key conventions

- **Software sources**: use `nvfetcher` to manage non-nixpkgs sources
- **Secret management**: reference external `secrets` flake (via sops-nix)

## Git commit rules

- Before commit, run pre-commit once inside direnv environment (for example:
  `direnv exec . pre-commit run -a`)
- Prefer `Conventional Commits` format for git commits; title in **English**, body in **Chinese**
