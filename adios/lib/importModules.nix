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
    filter
    ;

  matchNixFile = match "(.+)\.nix$";

  moduleArgs = {
    inherit adios;
  };
in
rootPath:
let
  files = readDir rootPath;
  filenames = attrNames files;

  moduleDirs = filter (
    name: files.${name} == "directory" && pathExists "${rootPath}/${name}/default.nix"
  ) filenames;

in
listToAttrs (
  map (name: {
    inherit name;
    value = import "${rootPath}/${name}/default.nix" moduleArgs;
  }) moduleDirs
)
// listToAttrs (
  concatMap (
    filename:
    if files.${filename} == "directory" then
      [ ]
    else
      (
        let
          m = matchNixFile filename;
          moduleName = head m;
        in
        if m == null then
          [ ]
        else
          [
            {
              name =
                if moduleDirs ? ${moduleName} then
                  throw ''
                    Module ${moduleName} was provided by both:
                    - ${rootPath}/${moduleName}/default.nix
                    - ${filename}

                    This is ambigious. Restructure your code to not have ambigious module names.
                  ''
                else
                  moduleName;
              value = import "${rootPath}/${filename}" moduleArgs;
            }
          ]
      )
  ) filenames
)
