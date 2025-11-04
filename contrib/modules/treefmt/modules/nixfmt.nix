{ adios }:
{
  name = "treefmt-nixfmt";

  options = {
    package = {
      type = adios.types.derivation;
      defaultFunc = { inputs, ... }: inputs."treefmt".pkgs.nixfmt;
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
      name = "nixfmt";
      treefmt = {
        command = inputs.treefmt.pkgs.lib.getExe options.package;
        includes = [ "*.nix" ];
      };
    };
}
