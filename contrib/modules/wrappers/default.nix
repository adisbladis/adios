{ adios }:
let
  inherit (adios) types;
  inherit (types)
    optionalAttr
    listOf
    bool
    string
    ;

  strings = listOf string;

  stringAttrs = optionalAttr (types.attrsOf types.string);

  prefixedEnv = listOf (
    types.struct "env" {
      name = types.string;
      value = types.string;
      sep = types.string;
    }
  );

in
{
  options = {
    name = {
      type = types.str;
      default = "wrapper";
    };

    paths = {
      type = listOf types.derivation;
      default = [ ];
    };

    # set the name of the executed process to NAME
    # (if unset or empty, defaults to EXECUTABLE)
    argv0.type = string;

    # the executable inherits argv0 from the wrapper.
    # (use instead of --argv0 '$0')
    inheritArgv0.type = bool;

    # if argv0 doesn't include a / character, resolve it against PATH
    resolveArgv0.type = bool;

    # prepend the whitespace-separated list of arguments ARGS to the invocation of the executable
    addFlags.type = strings;
    # append the whitespace-separated list of arguments ARGS to the invocation of the executable
    appendFlags.type = strings;

    # change working directory (use instead of --run "cd DIR")
    chdir.type = types.string;

    # add VAR with value VAL to the executable's environment
    env.type = stringAttrs;
    # like --set, but only adds VAR if not already set in the environment
    setDefaultEnv.type = stringAttrs;
    # remove VAR from the environment
    unsetEnv.type = strings;
    # suffix/prefix ENV with VAL, separated by SEP
    prefixEnv.type = prefixedEnv;
    suffixEnv.type = prefixedEnv;
  };

  inputs = {
    "nixpkgs" = {
      path = "/nixpkgs";
    };
  };

  impl =
    { inputs, options }:
    let
      inherit (inputs."nixpkgs") pkgs;
    in
    pkgs.runCommand options.name
      {
        nativeBuildInputs = [
          pkgs.makeBinaryWrapper
          pkgs.python3
          pkgs.lndir
        ];
        __structuredAttrs = true;
        inherit options;
      }
      ''
        source <(python3 ${./builder.py})
      '';
}
