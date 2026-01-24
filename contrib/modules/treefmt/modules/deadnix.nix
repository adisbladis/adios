adios:
{
  name = "treefmt-deadnix";

  options = {
    package = {
      type = adios.types.derivation;
      defaultFunc = { inputs }: inputs."nixpkgs".pkgs.deadnix;
    };
  };

  inputs = {
    "nixpkgs" = {
      path = "/nixpkgs";
    };
  };

  impl =
    { options, inputs }:
    let
      inherit (inputs."nixpkgs") pkgs;
      inherit (pkgs) lib;
    in
    {
      name = "deadnix";
      treefmt = {
        command = lib.getExe options.package;
        options = [ "--edit" ];
        includes = [ "*.nix" ];
      };
    };
}
