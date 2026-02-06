{ adios }:

let
  inherit (builtins)
    attrNames
    pathExists
    readDir
    concatMap
    listToAttrs
    match
    head
    ;

  matchNixFile = match "(.+)\.nix$";
  moduleArgs = adios;
in
rootPath:
let
  files = readDir rootPath;
  filenames = attrNames (readDir rootPath);
in
listToAttrs (
  concatMap (
    name:
    if files.${name} == "directory" then
      if pathExists "${toString rootPath}/${name}/default.nix" then
        [
          {
            inherit name;
            value = import "${toString rootPath}/${name}/default.nix" moduleArgs;
          }
        ]
      else
        [ ]
    else
      let
        m = matchNixFile name;
        moduleName = head m;
      in
      if m == null || name == "default.nix" then
        [ ]
      else
        [
          {
            name =
              if files ? ${moduleName} then
                throw ''
                  Module ${moduleName} was provided by both:
                  - ${rootPath}/${moduleName}/default.nix
                  - ${name}

                  This is ambigious. Restructure your code to not have ambigious module names.
                ''
              else
                moduleName;
            value = import "${toString rootPath}/${name}" moduleArgs;
          }
        ]
  ) filenames
)
