# module/git.nix
{ adios }:
let
  inherit (adios) types;
in
{
  options = {
    settings = {
      type = types.attrs;
      mutatorType = types.attrs;
      mergeFunc = adios.lib.merge.attrs.recursively;
    };
  };
}
