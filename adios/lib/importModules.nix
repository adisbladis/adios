{ adios }:

let
  inherit (builtins)
    attrNames
    foldl'
    pathExists
    readDir
    ;

  foldlAttrs =
    f: init: set:
    foldl' (acc: name: f acc name set.${name}) init (attrNames set);
in
rootPath:
foldlAttrs (
  acc: module: type:
  if type != "directory" || !pathExists "${rootPath}/${module}/default.nix" then
    acc
  else
    acc
    // {
      ${module} = import "${rootPath}/${module}" { inherit adios; };
    }
) { } (readDir rootPath)
