# Helper functions

## `importModules`

Adios comes with a function `importModules`, that will automatically import all the modles in a directory (provided they
follow a certain schema).

### Usage

Given this directory structure:

```
./modules
├── default.nix
├── foo
│   └── default.nix
└── bar
    ├── baz
    │   └── default.nix
    └── default.nix
```

If the root module at `default.nix` is defined like this:
```nix
{{#include root.nix}}
```

Then `importTree` will generate:
```nix
{{#include rootExpanded.nix}}
```

Notably, `importModules` is _not_ recursive - the `baz/` module was completely ignored. If the `bar` module wants to
depend on another module defined within its folder, it should import those modules itself, like this:
```nix
{{#include bar.nix}}
```

### Limitations

`importTree` expects all modules to:
- be defined in subfolders, under `$MODULE_NAME/default.nix`.
- take `{ adios }:` as the file's inputs
- use the same name as the folder it's contained within

If your module tree doesn't follow this schema, then it's recommended to define your import logic manually. `importTree`
is only a convenience function, and it's okay to not use it if your tree doesn't fit its schema.
