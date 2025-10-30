{
  pkgs ? import __sources.nixpkgs { },
  __sources ? import ./npins,
}:

let
  inherit (import ./.) adios adios-contrib;

  treefmt =
    let
      # Load a module definition tree.
      # This type checks modules and provides the tree API.
      tree = adios adios-contrib;

      # Apply options to tree
      eval = tree.eval {
        options = {
          "." = {
            inherit pkgs;
          };
        };
      };

      # Call treefmt contracts with applied pkgs
      treefmt = eval.tree.modules.treefmt;
      fmts = treefmt.modules;
    in
    (treefmt {
      projectRootFile = "flake.nix";
      formatters = [
        (fmts.nixfmt { })
        (fmts.deadnix { })
        (fmts.statix { })
      ];
    }).package;

in
pkgs.mkShell {
  packages = [
    pkgs.npins
    pkgs.nix-unit
    treefmt
    pkgs.mdbook
  ];
}
