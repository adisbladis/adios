{ adios }:
{
  name = "treefmt-deadnix";

  options = {
    package = {
      type = adios.types.derivation;
      defaultFunc = { inputs, ... }: inputs."treefmt".pkgs.deadnix;
    };
  };

  inputs = {
    "treefmt" = {
      path = "^";
    };
  };

  impl =
    { options, inputs }:
    {
      name = "deadnix";
      treefmt = {
        command = inputs.treefmt.pkgs.lib.getExe options.package;
        options = [ "--edit" ];
        includes = [ "*.nix" ];
      };
    };
}
