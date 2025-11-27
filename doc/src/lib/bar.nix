{ adios }:

{
  name = "bar";
  # Other contents omitted
  modules = adios.lib.importModules ./.;
}
