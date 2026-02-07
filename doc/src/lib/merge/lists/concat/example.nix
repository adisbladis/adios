# modules/environment.nix
{ adios }:
let
  inherit (adios) types;
in
{
  options = {
    systemPackages = {
      type = types.listOf types.derivation;
      mutatorType = types.listOf types.derivation;
      mergeFunc = adios.lib.merge.lists.concat;
    };
  };
}
