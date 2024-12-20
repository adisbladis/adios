# Concept

## Modules

### Module definition

A minimal Adios module definition is a function that takes a structured argument, and retuns an attribute set with a name as a string.
``` nix
{{#include minimal.nix}}
```

### Module loading

The module definition then needs to be _loaded_ by the adios loader function:
``` nix
adios ({{#include minimal.nix}})
```

Module loading is responsible for

- Injecting top-level arguments such as:
  - `adios` the module system
  - `types` alias for `adios.types`
  - `lib` nixpkgs lib
  - `self` a reference to the loaded module

- Wrapping the module definition with a type checker

  Module definitions are strictly typed and checked.

- Wrapping callable module implementations with options type checking

### Callable modules

Callable modules are modules with an `impl` function that takes an attrset with their arguments defined in `options`:
``` nix
{{#include callable.nix}}
```

Note that module returns are not type checked.
It is expected to pass the return value of a module into another module until you have a value that can be consumed.

### Laziness

Korora does eager evaluation when type checking values.
Adios module type checking however is lazily, with some caveats:

- Each option, type, test, etc returned by a module are checked on-access

- When calling a module each passed option is checked lazily

But defined `struct`'s, `listOf` etc thunks will be forced.
It's best for options definitions to contain a minimal interface to minimize the overhead of eager evaluation.
