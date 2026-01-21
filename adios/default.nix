let
  types = import ./types.nix {
    korora = import ../types/types.nix;
  };

  # Helper functions for users, accessed through `adios.lib`
  lib = {
    importModules = import ./lib/importModules.nix { inherit adios; };
  };

  inherit (builtins)
    attrNames
    listToAttrs
    mapAttrs
    concatMap
    isAttrs
    genericClosure
    filter
    isString
    split
    head
    tail
    foldl'
    attrValues
    substring
    concatStringsSep
    intersectAttrs
    functionArgs
    ;

  optionalAttrs = cond: attrs: if cond then attrs else { };

  # A coarse grained options type for input validation
  optionsType = types.attrsOf types.attrs;

  # Default in error messages when no name is provided
  anonymousModuleName = "<anonymous>";

  # Call a function with only it's supported attributes.
  callFunction = fn: attrs: fn (intersectAttrs (functionArgs fn) attrs);

  # Compute options from defaults & provided args
  computeOptions =
    let
      checkOption =
        errorPrefix: option: value:
        let
          err = option.type.verify value;
        in
        if err != null then (throw "${errorPrefix}: ${err}") else value;
    in
    {
      # Computed args fixpoint
      args,
      # Error prefix string
      errorPrefix,
      # Defined options
      options,
      # Passed options
      passedArgs,
    }:
    listToAttrs (
      concatMap (
        name:
        let
          option = options.${name};
          errorPrefix' = "${errorPrefix}: in option '${name}'";
        in
        # Explicitly passed value
        if passedArgs ? ${name} then
          [
            {
              inherit name;
              value = checkOption errorPrefix' option passedArgs.${name};
            }
          ]
        # Default value
        else if option ? default then
          [
            {
              inherit name;
              value = checkOption errorPrefix' option option.default;
            }
          ]
        # Computed default value
        else if option ? defaultFunc then
          [
            {
              # Compute value with args fixpoint
              inherit name;
              value = checkOption errorPrefix' option (callFunction option.defaultFunc args);
            }
          ]
        # Compute nested options
        else if option ? options then
          let
            value = computeOptions {
              inherit args;
              errorPrefix = errorPrefix';
              options = options.${name};
              passedArgs = passedArgs.${name} or { };
            };
          in
          # Only return a value if suboptions actually returned anything
          if value != { } then [ { inherit name value; } ] else [ ]
        # Nothing passed & no default. Leave unset.
        else
          [ ]
      ) (attrNames options)
    );

  # Lazy typecheck options
  checkOptionsType =
    errorPrefix: options:
    mapAttrs (
      name: option:
      if option ? options then
        { options = checkOptionsType "${errorPrefix}: in option '${name}'" option.options; }
      else
        let
          err = types.modules.option.verify option;
        in
        if err != null then throw "${errorPrefix}: in option '${name}': type error: ${err}" else option
    ) options;

  # Lazy type check an attrset
  checkAttrsOf =
    errorPrefix: type: value:
    let
      err = type.verify value;
    in
    if err == null then
      value
    else if isAttrs value then
      mapAttrs (name: checkAttrsOf "${errorPrefix}: in attr '${name}'" type) value
    else
      throw "${errorPrefix}: in attr: ${err}";

  # Check a single type with error prefix
  checkType =
    errorPrefix: type: value:
    let
      err = type.verify value;
    in
    if err == null then value else throw "${errorPrefix}: ${err}";

  # Type check a module lazily
  loadModule =
    def:
    let
      errorPrefix =
        if def ? name then "in module ${types.string.check def.name def.name}" else "in module";
    in
    # The loaded module instance
    {
      options = checkOptionsType "${errorPrefix} options definition" (def.options or { });

      modules = mapAttrs (_: loadModule) (def.modules or { });

      lib = checkType "${errorPrefix}: while checking 'lib'" types.modules.lib (def.lib or { });

      types = checkAttrsOf "${errorPrefix}: while checking 'types'" types.modules.typedef (
        def.types or { }
      );

      inputs = checkAttrsOf "${errorPrefix}: while checking 'inputs'" types.modules.input (
        def.inputs or { }
      );
    }
    // (optionalAttrs (def ? name) {
      name = checkType "${errorPrefix}: while checking 'name'" types.string def.name;
    })
    // (optionalAttrs (def ? impl) {
      impl = checkType "${errorPrefix}: while checking 'impl'" types.function def.impl;
    });

  # Merge lhs & rhs recursing into suboptions
  mergeOptionsUnchecked =
    options: lhs: rhs:
    lhs
    // rhs
    // listToAttrs (
      concatMap (
        optionName:
        let
          option = options.${optionName};
        in
        if option ? options then
          [
            {
              name = optionName;
              value = mergeOptionsUnchecked option.options (lhs.${optionName} or { }) (rhs.${optionName} or { });
            }
          ]
        else
          [ ]
      ) (attrNames options)
    );

  # Split string by separator
  splitString = sep: s: filter isString (split sep s);

  # Return absolute module path relative to pwd
  absModulePath =
    pwd: path: toString (if substring 0 1 path == "/" then /. + path else /. + pwd + "/${path}");

  # Get a module by it's / delimited path
  getModule =
    module: name:
    assert name != "";
    if name == "/" then
      module
    else
      let
        tokens = splitString "/" name;
      in
      # Assert that module input begins with a /
      if head tokens != "" then
        throw ''
          Module path `${name}` didn't start with a slash, when it was expected to.
          This likely means you used the incorrect name during the eval stage.
          A module path should look something like "/nixpkgs", which refers to `root.modules.nixpkgs`,
          and lets us set the options for that module.
        ''
      else
        foldl' (
          module: tok:
          if !module.modules ? ${tok} then
            throw ''
              Module path `${tok}` wasn't a child module of `${module.name or anonymousModuleName}`.
              Valid children of `${module.name}`: [${concatStringsSep ", " (attrNames module.modules)}]
            ''
          else
            module.modules.${tok}
        ) module (tail tokens);

  # Resolve required module dependencies for defined config options
  resolveTree =
    scope: moduleNames:
    listToAttrs (
      map
        (x: {
          name = x.key;
          value = getModule scope x.key;
        })
        (genericClosure {
          # Get startSet from passed config
          startSet = map (key: {
            inherit key;
          }) moduleNames;
          # Discover module dependencies
          operator =
            { key }:
            map (input: {
              key = absModulePath key input.path;
            }) (attrValues (getModule scope key).inputs);
        })
    );

  evalModuleTree =
    {
      # Passed options
      options,
      # Resolved modules attrset
      resolution,
      # Previous eval memoisation
      memoArgs ? { },
      memoResults ? { },
    }:
    rec {
      # Computed options/inputs for each module in resolution
      args =
        mapAttrs (modulePath: module: {
          inputs = mapAttrs (_: input: args.${input.path}.options) module.inputs;
          options = computeOptions {
            args = args.${modulePath};
            errorPrefix = "while computing ${modulePath} args";
            inherit (module) options;
            passedArgs = options.${modulePath} or { };
          };
        }) resolution
        // memoArgs;

      inherit options resolution;

      # Module call results for each callable module in resolution
      results =
        listToAttrs (
          concatMap (
            modulePath:
            let
              module = resolution.${modulePath};
            in
            if module ? impl then
              [
                {
                  name = modulePath;
                  value = callFunction module.impl args.${modulePath};
                }
              ]
            else
              [ ]
          ) (attrNames resolution)
        )
        // memoResults;
    };

  computeArgs =
    {
      root,
      module,
      modulePath,
      # Options to be injected
      passedArgs,
    }:
    let
      args = {
        inputs = mapAttrs (
          _: input: (getModule root (absModulePath modulePath input.path)).args.options
        ) module.inputs;
        options = computeOptions {
          inherit args;
          errorPrefix = "while computing ${modulePath} args";
          inherit (module) options;
          passedArgs = passedArgs.${modulePath} or { };
        };
      };
    in
    args;

  # Apply options to a module tree, returning a new module tree where modules can be called
  # with their inputs already wired up & options partially applied.
  applyTreeOptions =
    {
      # Root module
      root,
      # Passed options
      options,
      # Attrset of computed args from tree eval context
      args,
    }:
    let
      recurse =
        # Path to current module as a list of string
        modulePath':
        # Current module
        module:
        let
          # Create submodule path string
          modulePath = "/" + concatStringsSep "/" modulePath';

          self =
            module
            // {
              # Take args from resolved context if it's available there.
              args =
                args.${modulePath} or (computeArgs {
                  module = self;
                  root = tree';
                  inherit modulePath;
                  passedArgs = options;
                });
              # Recurse into child modules
              modules = mapAttrs (moduleName: recurse (modulePath' ++ [ moduleName ])) module.modules;
            }
            // optionalAttrs (module ? impl) {
              # Wrap module call with computed args
              __functor =
                let
                  passedOptions = options.${modulePath} or { };
                in
                self: options:
                let
                  # Concat passed options with options passed to tree eval
                  options' = mergeOptionsUnchecked self.options passedOptions options;
                  # Re-compute args fixpoint with passed args
                  args = {
                    inherit (self.args) inputs;
                    options = computeOptions {
                      inherit args;
                      errorPrefix = "while calling ${modulePath}";
                      inherit (module) options;
                      passedArgs = options';
                    };
                  };
                in
                # Call implementation
                callFunction self.impl args;
            };
        in
        self;

      tree' = recurse [ ] root;
    in
    tree';

  mkOverride =
    root: prevEval:
    {
      # Updated options
      options ? { },
      # Whether to allow re-resolving
      resolve ? true,
    }:
    optionsType.check options (
      let
        # TODO: Filter nulled out options
        options' = prevEval.options // options;

        # Names of all modules being updated
        moduleNames = attrNames options;

        # Names of all modules being referenced in the new options, but not present
        # in the old module resolution.
        # If this list is non-empty modules have to be re-resolved.
        newModuleNames = filter (name: !prevEval.resolution ? ${name}) moduleNames;

        # Module dependency resolution
        resolution =
          if newModuleNames != [ ] then
            (
              if resolve then
                resolveTree root (attrNames options')
              else
                throw ''
                  Module overriding caused re-resolving, which is disabled.
                  Differing modules: ${concatStringsSep " " newModuleNames}
                ''
            )
          else
            prevEval.resolution;

        # Resolve which module options/results needs to be invalidated
        diff =
          let
            resolutionNames = attrNames resolution;
          in
          map (result: result.key) (genericClosure {
            startSet = map (key: { inherit key; }) moduleNames;
            operator =
              { key }:
              concatMap (
                name: if resolution.${name}.inputs ? ${key} then [ { key = name; } ] else [ ]
              ) resolutionNames;
          });
      in
      rec {
        # Overriden eval context
        evalParams = evalModuleTree {
          inherit resolution;
          options = options';
          memoArgs = removeAttrs prevEval.args diff;
          memoResults = removeAttrs prevEval.results diff;
        };

        # Tree context
        root = applyTreeOptions {
          inherit root;
          options = options';
          inherit (evalParams) args;
        };

        # Chained override function
        override = mkOverride root evalParams;
      }
    );

  # Load a module tree recursively from root module
  loadTree =
    root:
    let
      root' = loadModule root;
    in
    {
      root = root';

      eval =
        {
          options ? { },
        }:
        optionsType.check options rec {
          # Eval context
          evalParams =
            let
              resolution = resolveTree root' (attrNames options);
            in
            evalModuleTree { inherit resolution options; };

          # Tree context
          root = applyTreeOptions {
            root = root';
            inherit options;
            inherit (evalParams) args;
          };

          # Chained override function
          override = mkOverride root' evalParams;
        };
    };

  adios =
    (loadModule {
      name = "adios";
      inherit types lib;
    })
    // {
      # Overwrite default functor with one that _does not_ do type checking.
      # `load` does it's own type checking.
      __functor = _: loadTree;
    };

in
adios
