let
  types = import ./types.nix {
    korora = import ../types/types.nix;
  };

  # Helper functions for users, accessed through `adios.lib`
  lib = {
    importModules = import ./lib/importModules.nix { inherit adios; };
  };

  inherit (builtins)
    any
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
    typeOf
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

      publish = checkType "${errorPrefix}: while checking 'publish'" types.modules.publish (
        def.publish or [ ]
      );

      subscribe = checkType "${errorPrefix}: while checking 'subscribe'" types.modules.subscribe (
        def.subscribe or [ ]
      );

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
    })
    // (optionalAttrs (def ? contract) (
      if def ? inputs && def.inputs != { } then
        throw "${errorPrefix}: a contract module cannot have 'inputs'"
      else if def ? publish && def.publish != [ ] then
        throw "${errorPrefix}: a contract module cannot have 'publish'"
      else if def ? subscribe && def.subscribe != [ ] then
        throw "${errorPrefix}: a contract module cannot have 'subscribe'"
      else
        {
          contract =
            checkType "${errorPrefix}: while checking 'contract'" types.modules.contract
              def.contract;
        }
    ));

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
          Module path `${name}` does not start with a slash.
          Module paths should look like "/nixpkgs", which refers to `root.modules.nixpkgs`.
        ''
      else
        foldl' (
          module: tok:
          if !module.modules ? ${tok} then
            throw ''
              Module path `${tok}` is not a child module of `${module.name or anonymousModuleName}`.
              Valid children of `${module.name or anonymousModuleName}`: [${concatStringsSep ", " (attrNames module.modules)}]
            ''
          else
            module.modules.${tok}
        ) module (tail tokens);

  /**
      Walk the module tree and build a registry of contract publishers and subscribers.
      This avoids walking the tree again if multiple subscribers exist.
      Validates that publish/subscribe targets point to modules with `contract`.

    {
      # What is being published
      "/user" = {
        # The 'name' of the contract
        # - result.${name}
        # - subscription.${name}
        name = "user";
        publishers = [
          # Who publishes
          "/producer1"
          "/producer2"
        ];
        subscribers = [
          # Who subscribes
          "/users";
        ];
      };
    }
  */
  buildRegistry =
    root:
    let
      walk =
        modulePath': module:
        let
          modulePath = "/" + concatStringsSep "/" modulePath';
        in
        (concatMap (
          contractPath:
          let
            contractMod = getModule root contractPath;
          in
          if !(contractMod ? contract) then
            throw "Module '${modulePath}' publishes to '${contractPath}', but that module has no 'contract' field"
          else
            [
              {
                inherit contractPath;
                type = "publisher";
                path = modulePath;
              }
            ]
        ) module.publish)
        ++ (concatMap (
          contractPath:
          let
            contractMod = getModule root contractPath;
          in
          if !(contractMod ? contract) then
            throw "Module '${modulePath}' subscribes to '${contractPath}', but that module has no 'contract' field"
          else
            [
              {
                inherit contractPath;
                type = "subscriber";
                path = modulePath;
              }
            ]
        ) module.subscribe)
        # Recurse into child modules
        ++ concatMap (moduleName: walk (modulePath' ++ [ moduleName ]) module.modules.${moduleName}) (
          attrNames module.modules
        );

      entries = walk [ ] root;

      # Group by contract path
      grouped = foldl' (
        acc: entry:
        let
          prev =
            acc.${entry.contractPath} or {
              name = contractNameFromPath entry.contractPath;
              publishers = [ ];
              subscribers = [ ];
            };
        in
        acc
        // {
          ${entry.contractPath} =
            if entry.type == "publisher" then
              prev // { publishers = prev.publishers ++ [ entry.path ]; }
            else
              prev // { subscribers = prev.subscribers ++ [ entry.path ]; };
        }
      ) { } entries;
    in
    grouped;

  # Resolve required module dependencies for defined config options
  resolveTree =
    scope: registry: moduleNames:
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
            let
              mod = getModule scope key;
              # Regular input dependencies
              inputDeps = map (input: {
                key = absModulePath key input.path;
              }) (attrValues mod.inputs);
              # Subscribe dependencies: pull in all publishers + the contract module
              subscribeDeps = concatMap (
                contractPath:
                let
                  entry = registry.${contractPath};
                in
                [ { key = contractPath; } ] ++ map (pub: { key = pub; }) entry.publishers
              ) mod.subscribe;
            in
            inputDeps ++ subscribeDeps;
        })
    );

  evalModuleTree =
    {
      # Passed options
      options,
      # Resolved modules attrset
      resolution,
      # Contract registry
      registry,
      # Previous eval memoisation
      memoArgs ? { },
      memoResults ? { },
    }:
    rec {
      # Computed options/inputs for each module in resolution
      args =
        mapAttrs (modulePath: module: {
          inputs = mapAttrs (_: input: args.${absModulePath modulePath input.path}.options) module.inputs;

          # Map input names to the impl return value of the referenced module
          results = mapAttrs (
            inputName: input:
            let
              depPath = absModulePath modulePath input.path;
            in
            if results ? ${depPath} then
              results.${depPath}
            else
              throw "Module '${depPath}' (input '${inputName}' of '${modulePath}') has no impl, so it has no result"
          ) module.inputs;

          # Compute subscriptions: for each subscribed contract, merge all published values
          subscriptions = listToAttrs (
            map (
              contractPath:
              let
                entry = registry.${contractPath};
                contractMod = resolution.${contractPath};
                # Gather the published values from each publisher's result
                publishers = builtins.listToAttrs (
                  map (
                    pubPath:
                    let
                      pubResult = results.${pubPath};
                    in
                    {
                      name = pubPath;
                      value =
                        if pubResult ? ${entry.name} then
                          pubResult.${entry.name}
                        else
                          throw "Module '${pubPath}' publishes to '${contractPath}' but its result has no '${entry.name}' attribute";
                    }
                  ) entry.publishers
                );
              in
              {
                name = entry.name;
                value = contractMod.contract.merge publishers;
              }
            ) module.subscribe
          );

          options = computeOptions {
            args = args.${modulePath};
            errorPrefix = "while computing ${modulePath} args";
            inherit (module) options;
            passedArgs = options.${modulePath} or { };
          };
        }) resolution
        // memoArgs;

      inherit options resolution registry;

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
                  value = validatePublished (p: resolution.${p}) modulePath module.publish (
                    callFunction module.impl args.${modulePath}
                  );
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

        results = mapAttrs (
          inputName: input:
          let
            dep = getModule root (absModulePath modulePath input.path);
          in
          if dep ? impl then
            callFunction dep.impl dep.args
          else
            throw "Module at input '${inputName}' of '${modulePath}' has no impl, so it has no result"
        ) module.inputs;

        # Subscriptions are only available in the tree eval context (evalModuleTree).
        # Calling a subscribing module directly via __functor outside that context
        # will throw when accessing subscriptions.
        subscriptions =
          builtins.mapAttrs
            (
              _: _: throw "Module '${modulePath}' has subscriptions but was called outside the tree eval context"
            )
            (
              listToAttrs (
                map (contractPath: {
                  name = contractNameFromPath contractPath;
                  value = null;
                }) module.subscribe
              )
            );

        options = computeOptions {
          inherit args;
          errorPrefix = "while computing ${modulePath} args";
          inherit (module) options;
          passedArgs = passedArgs.${modulePath} or { };
        };
      };
    in
    args;

  /**
    Extracts the contract name from a contract module path.

    The contract name is used as the key for:
    - publisher results: `result.${name}`
    - subscriber subscriptions: `subscriptions.${name}`

    # Arguments
    - `path`: A contract module path (e.g. "/foo/bar/user")

    # Returns
    The last segment of the path (e.g. "user")

    # Consumers
    - `buildRegistry`: to set `name` on registry entries
    - `validatePublished`: to look up the published key in a module's result
  */
  contractNameFromPath =
    path:
    let
      tokens = filter isString (split "/" path);
    in
    builtins.elemAt tokens (builtins.length tokens - 1);

  /**
    Validates a module's published outputs against their contracts.

    Checks that the result contains the expected key for each
    published contract, then validates every element in the collection
    by running it through the contract module's options and impl.

    # Arguments
    - getContractMod: lookup function
      - `evalModuleTree` passes `(p: resolution.${p})`
      - `__functor` passes `(p: getModule tree' p)`
    - `modulePath`: Path of the publishing module (for error reporting)
    - `publishPaths`: list of e.g. `[ "/user" "/etcFile" ]`
    - `result`: The return value of `impl`

    # Returns

    The result with published attributes replaced by their validated versions.
    NOTE: The contract may apply transformations that go beyond type checking.

    # Consumers
    - `evalModuleTree.results`: validates results during tree evaluation
    - `applyTreeOptions.__functor`: validates results on direct module calls
  */
  validatePublished =
    getContractMod: modulePath: publishPaths: result:
    if publishPaths == [ ] then
      result
    else
      let
        publishNames = map contractNameFromPath publishPaths;
        missing = filter (name: !result ? ${name}) publishNames;
      in
      if missing != [ ] then
        throw ''
          Module '${modulePath}' declares to publish '[ ${concatStringsSep " " missing} ]' but impl doesnt return it
        ''
      else
        let
          validated = listToAttrs (
            map (
              contractPath:
              let
                name = contractNameFromPath contractPath;
                raw = result.${name};
                contractMod = getContractMod contractPath;
                validate =
                  resource:
                  callFunction contractMod.impl {
                    options = computeOptions {
                      args = {
                        options = resource;
                      };
                      errorPrefix = "while validating '${name}' published by '${modulePath}'";
                      options = contractMod.options;
                      passedArgs = resource;
                    };
                  };
              in
              {
                inherit name;
                value =
                  if isAttrs raw then
                    mapAttrs (_: validate) raw
                  else if builtins.isList raw then
                    map validate raw
                  else
                    throw "Module '${modulePath}' published '${name}' must be an attrset or list, got ${typeOf raw}";
              }
            ) publishPaths
          );
        in
        result // validated;

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
      # Contract registry
      registry,
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
                        inherit (self.args) inputs results subscriptions;
                        options = computeOptions {
                          inherit args;
                          inherit (module) options;
                          errorPrefix = "while calling ${modulePath}";
                          # Concat passed options with options passed to tree eval
                          passedArgs = mergeOptionsUnchecked self.options passedOptions implOptions;
                        };
                      };
                in
                validatePublished (p: getModule tree' p) modulePath self.publish (callFunction self.impl args);
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
      # Whether to allow re-resolvingq
      resolve ? true,
    }:
    optionsType.check options (
      let
        registry = prevEval.registry;

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
                resolveTree root registry (attrNames options')
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
                name:
                let
                  mod = resolution.${name};
                in
                # Inputs invalidate
                if any (input: absModulePath name input.path == key) (attrValues mod.inputs) then
                  [ { key = name; } ]
                # Pub/sub invalidate
                # 1. Contract changes -> invalidate all subscribers
                # 2. Publisher changes -> invalidate all subscribers
                else if
                  any (
                    contractPath:
                    let
                      entry = registry.${contractPath};
                    in
                    key == contractPath || builtins.elem key entry.publishers
                  ) mod.subscribe
                then
                  [ { key = name; } ]
                else
                  [ ]
              ) resolutionNames;
          });

        # Overriden eval context
        evalParams = evalModuleTree {
          inherit resolution registry;
          options = options';
          memoArgs = removeAttrs prevEval.args diff;
          memoResults = removeAttrs prevEval.results diff;
        };
        # Tree context
        tree = applyTreeOptions {
          inherit root registry;
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
      registry = buildRegistry root;
    in
    {
      options ? { },
    }:
    let
      # Collect all subscriber module paths from registry so they're always resolved
      subscriberPaths = concatMap (regEntry: regEntry.subscribers) (attrValues registry);

      # Overriden eval context
      evalParams =
        let
          resolution = resolveTree root registry (attrNames options ++ subscriberPaths);
        in
        evalModuleTree { inherit resolution registry options; };
      # Tree context
      tree = applyTreeOptions {
        inherit root options registry;
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
