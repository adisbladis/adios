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

      # Load the root module into adios
      # This type checks modules and provides the tree API.
      # Recursive update function works just like `//`, where the right side
      # takes priority if the value already exists
      root = adios (pkgs.lib.recursiveUpdate adios-contrib overrides);

      # Apply options to tree
      tree = root.eval {
        options = {
          "/nixpkgs" = {
            inherit pkgs;
          };
        };
      };
    in
    # Call treefmt contracts with applied pkgs
    tree.root.modules.treefmt {
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
