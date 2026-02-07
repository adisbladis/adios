let
  types = import ./types.nix {
    korora = import ../types/types.nix;
  };

  # Helper functions for users, accessed through `adios.lib`
  lib = {
    importModules = import ./lib/importModules.nix { inherit adios; };
    merge = {
      lists.concat = { mutators }: concatLists (attrValues mutators);
      strings.concatLines = { mutators }: concatStringsSep "\n" (attrValues mutators);
      attrs.flat = import ./lib/merge-attrs-flat.nix;
      attrs.recursively = import ./lib/merge-attrs-recursively.nix;
      general.withPrio = import ./lib/withPrio.nix;
    };
  };

  inherit (builtins)
    attrNames
    attrValues
    concatLists
    concatMap
    concatStringsSep
    filter
    foldl'
    functionArgs
    genericClosure
    head
    intersectAttrs
    isAttrs
    isString
    listToAttrs
    mapAttrs
    split
    substring
    tail
    ;

  optionalAttrs = cond: attrs: if cond then attrs else { };

  # A coarse grained options type for input validation
  optionsType = types.attrsOf types.attrs;

  # Default in error messages when no name is provided
  anonymousModuleName = "<anonymous>";

  # Call a function with only it's supported attributes.
  callFunction = fn: attrs: fn (intersectAttrs (functionArgs fn) attrs);

  printList = list: "[${concatStringsSep ", " list}]";

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
      modulePath,
      root ? null,
    }:
    listToAttrs (
      concatMap (
        name:
        let
          option = options.${name};
          errorPrefix' = "${errorPrefix}: in option '${name}'";
        in
        if option ? mutators then
          assert root != null;
          [
            {
              inherit name;
              value =
                let
                  err = types.modules.mutatedOption.verify option;
                in
                if err != null then
                  throw "${errorPrefix'}: type error: ${err}"
                else
                  checkOption errorPrefix' option (
                    callFunction option.mergeFunc (
                      args
                      // {
                        mutators = getMutators {
                          inherit
                            name
                            option
                            passedArgs
                            root
                            checkOption
                            modulePath
                            ;
                          errorPrefix = errorPrefix';
                        };
                      }
                    )
                  );
            }
          ]
        # Explicitly passed value
        else if passedArgs ? ${name} then
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
        # Gross hack - if you want a mergeFunc to be called without mutators,
        # set `mutators = []`.
        # Compute nested options
        else if option ? options then
          let
            # TODO: how to handle this?
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
    // (optionalAttrs (def ? mutations) {
      mutations =
        checkAttrsOf "${errorPrefix}: while checking 'mutations'" types.modules.mutation
          def.mutations;
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
              Valid children of `${module.name}`: ${printList (attrNames module.modules)}
            ''
          else
            module.modules.${tok}
        ) module (tail tokens);

  getMutators =
    {
      name,
      option,
      passedArgs,
      root,
      checkOption,
      modulePath,
      errorPrefix,
    }:
    listToAttrs (
      concatMap (
        mutatorPath':
        let
          mutatorPath = absModulePath modulePath mutatorPath';
          resolution = getModule root mutatorPath;
        in
        # TODO: decide whether to error here, if a module didn't
        # mutate when it was supposed to
        if resolution.mutations ? ${modulePath}.${name} then
          [
            {
              name = mutatorPath;
              value = checkOption ("${errorPrefix}: while checking type of mutator ${mutatorPath}") {
                type = option.mutatorType;
              } (callFunction resolution.mutations.${modulePath}.${name} resolution.args);
            }
          ]
        else
          [ ]
      ) option.mutators
    )
    # If the mutators list is nonempty, have the value passed in eval stage
    # option go through the mergeFunc, under the current module's name.
    // optionalAttrs (passedArgs ? ${name}) {
      ${modulePath} = checkOption ("${errorPrefix}: while checking type of injected value") {
        type = option.mutatorType;
      } passedArgs.${name};
    };

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

  # When inspecting the args passed to a module within an `impl` or
  # `defaultFunc`, include the functor to call the module's impl directly.
  inspectImpl =
    module: oldArgs:
    if module ? impl then
      oldArgs
      // {
        __functor = _: newArgs: module newArgs;
      }
    else
      oldArgs;

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
            inherit modulePath;
            inherit (module) options;
            args = args.${modulePath};
            errorPrefix = "while computing ${modulePath} args";
            passedArgs = options.${modulePath} or { };
          };
        }) resolution
        // memoArgs;

      inherit options resolution;

      # Module call results for each callable module in resolution
      # TODO: actually use this somewhere other than `mkOverride`
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
          _: input:
          let
            inputPath = absModulePath modulePath input.path;
            inputModule = getModule root inputPath;
          in
          inputModule.args.options
          // optionalAttrs (inputModule ? impl) {
            __functor =
              _: implOptions:
              let
                args =
                  # Reuse existing args if impl isn't being passed anything new
                  if implOptions == { } then
                    inputModule.args
                  else
                    # If any new args are passed, recompute the options, so any
                    # defaultFuncs are updated
                    {
                      inherit (inputModule.args) inputs;
                      options = computeOptions {
                        inherit args root;
                        inherit (inputModule) options;
                        errorPrefix = "while calling ${inputPath}";
                        modulePath = inputPath;
                        passedArgs = implOptions;
                      };
                    };
              in
              callFunction inputModule.impl args;
          }
        ) module.inputs;
        options = inspectImpl module (computeOptions {
          inherit args modulePath root;
          inherit (module) options;
          errorPrefix = "while computing ${modulePath} args";
          passedArgs = passedArgs.${modulePath} or { };
        });
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
                self: implOptions:
                let
                  passedOptions = options.${modulePath} or { };
                  args =
                    if implOptions == { } then
                      # Reuse existing args if impl isn't being passed anything new
                      self.args
                    else
                      # Re-compute args fixpoint with passed args
                      {
                        inherit (self.args) inputs;
                        options = inspectImpl self (computeOptions {
                          inherit args modulePath;
                          inherit (module) options;
                          root = tree';
                          errorPrefix = "while calling ${modulePath}";
                          # Concat passed options with options passed to tree eval
                          passedArgs = mergeOptionsUnchecked self.options passedOptions implOptions;
                        });
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

        # Overriden eval context
        evalParams = evalModuleTree {
          inherit resolution;
          options = options';
          memoArgs = removeAttrs prevEval.args diff;
          memoResults = removeAttrs prevEval.results diff;
        };
        # Tree context
        tree = applyTreeOptions {
          inherit root;
          options = options';
          inherit (evalParams) args;
        };
      in
      tree
      // {
        # Chained override function
        override = mkOverride root evalParams;
      }
    );

  # Load a module tree recursively from root module
  loadTree =
    unloadedRoot:
    let
      root = loadModule unloadedRoot;
    in
    {
      options ? { },
    }:
    let
      # Overriden eval context
      evalParams =
        let
          resolution = resolveTree root (attrNames options);
        in
        evalModuleTree { inherit resolution options; };
      # Tree context
      tree = applyTreeOptions {
        inherit root options;
        inherit (evalParams) args;
      };
    in
    tree
    // {
      # Chained override function
      override = mkOverride root evalParams;
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
