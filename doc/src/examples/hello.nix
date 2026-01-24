{ types, ... }:
{
  options = {
    enable = {
      type = types.bool;
      default = false;
    };

    package = {
      type = types.derivation;
      defaultFunc = { inputs }: inputs."nixpkgs".pkgs.hello;
    };
  };

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  impl =
    {
      options,
      inputs,
    }:
    let
      inherit (inputs.nixpkgs.pkgs) lib;
    in
    lib.optionalAttrs options.enable {
      packages = [
        options.package
      ];
    };
}
