{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShellNoCC {
        name = "dots";
        packages = with pkgs; [
          ast-grep
          bashInteractive
          deploy-rs
          nixfmt
          deadnix
          statix
          prettier
          nixos-anywhere
          actionlint
        ];
      };

      formatter = pkgs.nixfmt-tree;
    };
}
