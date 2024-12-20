{
  korora,
  lib,
}:

let
  types = import ./types.nix { inherit korora; };

  inherit (builtins)
    attrNames
    listToAttrs
    mapAttrs
    concatMap
    isAttrs
    isFunction
    ;
  inherit (types) struct;

  # Transform options into a default value attrset
  optionsToDefaults =
    errorPrefix: options:
    listToAttrs (
      concatMap (
        name:
        let
          option = options.${name};
        in
        if option ? default then
          [
            rec {
              inherit name;
              value =
                if err != null then "${errorPrefix}: in option '${name}': type error ${err}" else option.default;
              err = option.type.verify option.default;

            }
          ]
        else if option ? options then
          [
            {
              inherit name;
              value = optionsToDefaults "${errorPrefix}: in option '${name}'" option.options;
            }
          ]
        else
          [ ]
      ) (attrNames options)
    );

  # Update default values with new ones
  updateDefaults =
    errorPrefix: options: old: new:
    old
    // mapAttrs (
      name: value:
      if !options ? ${name} then
        throw "${errorPrefix}: applied option '${name}' does not exist"
      else
        let
          option = options.${name};
          err = option.type.verify value;
        in
        if option ? options then
          updateDefaults "${errorPrefix}: in option ${name}" option.options (old.${name} or { }) value
        else if err != null then
          throw "${errorPrefix}: in option '${name}': type error ${err}"
        else
          value
    ) new;

  # Traverse options, throwing for every unset value
  throwUnsetDefaults =
    errorPrefix: options: defaults:
    mapAttrs (
      name: option:
      if option ? options then
        throwUnsetDefaults "${errorPrefix} in option ${name}" option.options (
          defaults.${name} or (throw "${errorPrefix}: option '${name}' is unset")
        )
      else
        defaults.${name} or (throw "${errorPrefix}: option '${name}' is unset")
    ) options;

  # Transform options into a concrete struct type
  optionsToType =
    name: options:
    struct name (
      mapAttrs (
        name: option: if option ? options then optionsToType name option.options else option.type
      ) options
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

  # Apply one or more defaults to module.
  apply =
    moduleDef: updates:
    let
      # Call moduleDef with declared arguments
      args' = {
        inherit adios lib types;
        self = mod;
      };
      def = moduleDef (
        mapAttrs (n: _: args'.${n} or (throw "Module takes argument '${n}' which is unknown")) (
          lib.functionArgs moduleDef
        )
      );

      errorPrefix = "in module '${mod.name}'";

      options = checkOptionsType "${errorPrefix} options definition" (def.options or { });

      # Transform options into an attrset of default values
      defaults = updateDefaults errorPrefix options (optionsToDefaults errorPrefix options) updates;

      # Wrap implementation with an options typechecker
      impl' = def.impl;
      impl =
        if def ? impl then
          (args: impl' (updateDefaults "while calling module '${mod.name}'" options mod.defaults args))
        else if def ? name then
          _: throw "Module '${def.name}' is not callable"
        else
          _: throw "Module is not callable";

      # The loaded module instance
      mod = {
        inherit (def) name;

        apply = updates': apply moduleDef (updates // updates');

        modules = mapAttrs (_: load) (def.modules or { });

        types = checkAttrsOf "${errorPrefix}: while checking 'types'" types.modules.typedef (
          def.types or { }
        );

        interfaces = checkAttrsOf "${errorPrefix}: while checking 'interfaces'" types.modules.typedef (
          def.interfaces or { }
        );

        checks = checkAttrsOf "${errorPrefix}: while checking 'checks'" types.derivation (
          def.checks or { }
        );

        tests = checkAttrsOf "${errorPrefix}: while checking 'tests'" types.modules.nixUnitTest (
          def.tests or { }
        );

        inherit options;

        # For composability reasons optionsToDefaults cannot construct throws on options with no defaults.
        defaults = throwUnsetDefaults errorPrefix options defaults;

        type =
          def.type or (
            if def ? options then
              # Transform options into a struct type
              optionsToType def.name options
            else
              types.never
          );

        __functor = _: impl;
      };

    in
    if !isFunction moduleDef then
      throw "module definition is not a function"
    else if !def ? name then
      throw "module definition missing name attribute"
    else
      mod;

  load = moduleDef: apply moduleDef { };

  interfaces = import ./interfaces.nix { inherit types; };

  adios =
    (load (_: {
      name = "adios";
      inherit types interfaces;
      tests = import ./tests.nix { inherit adios lib; };

      type = types.union [
        types.modules.moduleDef
        types.function
      ];

      modules = {
        nix-unit = import ./modules/nix-unit.nix;
        checks = import ./modules/checks.nix;
      };
    }))
    // {
      # Overwrite default functor with one that _does not_ do type checking.
      # `load` does it's own type checking.
      __functor = _: load;
    };

in
adios
