# `merge.attrs.recursively`

## Behavior

This function takes the raw data from mutators each providing some attribute set, like this:

```nix
{{#include dataBefore.nix}}
```

And merges the values into:

```nix
{{#include dataAfter.nix}}
```

## Usage

This function should only be used if you want:

1. The option in question to be mutated by other modules
1. Attrsets with identical keys to be merged recursively
1. Other values with identical keys to throw an error

For example:

```nix
{{#include example.nix}}
```
