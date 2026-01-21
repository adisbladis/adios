{
  pkgs ? import __sources.nixpkgs { },
  __sources ? import ./npins,
}:

let
  inherit (import ./.) adios adios-contrib;

  treefmt =
    let
      # Load the root module into adios, and apply options to tree
      tree = adios adios-contrib {
        options = {
          "/nixpkgs" = {
            inherit pkgs;
          };
        };
      };

      # Call treefmt contracts with applied pkgs
      treefmt = tree.modules.treefmt;
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
