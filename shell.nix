{
  pkgs ? import __sources.nixpkgs { },
  __sources ? import ./npins,
}:

let
  inherit (import ./.) adios adios-contrib;

  treefmt =
    let
      # Inject some values into the root modules
      # We use a recursive update function, to take the generic modules and add
      # some opinionated config to them
      overrides = {
        modules = {
          treefmt.options.formatters.mutators = [
            "/treefmt/deadnix"
            "/treefmt/statix"
            "/treefmt/nixfmt"
          ];
        };
      };
      root = pkgs.lib.recursiveUpdate adios-contrib overrides;

      # Load the root module into adios, and apply options to tree
      tree = adios root {
        options = {
          "/nixpkgs" = {
            inherit pkgs;
          };
        };
      };
    in
    # Call treefmt contracts with applied pkgs
    tree.modules.treefmt {
      projectRootFile = "flake.nix";
    };

in
pkgs.mkShell {
  packages = [
    pkgs.npins
    pkgs.nix-unit
    treefmt
    pkgs.mdbook
    pkgs.mdbook-cmdrun
  ];
}
