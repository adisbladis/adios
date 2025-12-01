{
  pkgs ? import __sources.nixpkgs { },
  __sources ? import ./npins,
}:

let
  inherit (import ./.) adios adios-contrib;

  treefmt =
    let
      # Load the root module into adios
      # This type checks modules and provides the tree API.
      root = adios adios-contrib;

      # Apply options to tree
      tree = root.eval {
        options = {
          "/nixpkgs" = {
            inherit pkgs;
          };
        };
      };

      # Call treefmt contracts with applied pkgs
      treefmt = tree.root.modules.treefmt;
      fmts = treefmt.modules;
    in
    treefmt {
      projectRootFile = "flake.nix";
      formatters = [
        (fmts.nixfmt { })
        (fmts.deadnix { })
        (fmts.statix { })
      ];
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
