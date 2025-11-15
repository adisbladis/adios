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
      initializedTree = tree.init {
        options = {
          "/nixpkgs" = {
            inherit pkgs;
          };
        };
      };

      # Call treefmt contracts with applied pkgs
      treefmt = initializedTree.root.modules.treefmt;
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
    pkgs.mdbook-cmdrun
  ];
}
