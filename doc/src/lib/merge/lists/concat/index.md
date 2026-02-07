# `merge.lists.concat`

## Behavior

This function takes the raw data from mutators each providing a list, like this:
```nix
{{#include mutatorsBefore.nix}}
```

And turns it into:

```nix
{{#include mutatorsAfter.nix}}
```

The order might be different than you expected. `merge.lists.concat` sorts lexicographically based on the mutator path.
Since `/bar` comes before `/foo` in ASCII, the `bar` list ended up coming first.
## Usage

This should be used when:

1. You're creating an option that expects to be mutated.
1. The final result is expected to be a list of your desired value.
1. Each of the mutators provide a list of your desired value.
1. You don't care about the final order.

For example:

```nix
{{#include example.nix}}
```
