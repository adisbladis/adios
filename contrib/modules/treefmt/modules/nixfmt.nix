adios:
{
  name = "treefmt-nixfmt";

  options = {
    package = {
      type = adios.types.derivation;
      defaultFunc = { inputs }: inputs."nixpkgs".pkgs.nixfmt;
    };
  };

  inputs = {
    "nixpkgs" = {
      path = "/nixpkgs";
    };
  };

  mutations = {
    "/treefmt".formatters =
      { options, inputs }:
      let
        inherit (inputs."nixpkgs") pkgs;
        inherit (pkgs) lib;
      in
      {
        name = "nixfmt";
        treefmt = {
          command = lib.getExe options.package;
          includes = [ "*.nix" ];
        };
      };
  };
}
