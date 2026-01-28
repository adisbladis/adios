# `merge`

Adios now provides a way for one module to mutate another module's option. However, Adios doesn't come with merge
semantics. If an option wants to allow itself to be mutated, it must specify how the merging should be handled.

To help with the most common cases, Adios comes with some premade merge functions. These are namespaced within
`adios.lib` by the type that each mutator is expected to provide. Merge functions that expect any type go under the
`adios.lib.general` namespace.
