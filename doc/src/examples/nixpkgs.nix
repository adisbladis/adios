{ types, ... }:
{
  options = {
    pkgs = {
      type = types.attrs;
      default = import <nixpkgs> { };
    };
  };
}
