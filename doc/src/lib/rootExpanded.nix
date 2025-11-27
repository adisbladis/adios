{ adios }:

{
  name = "root";
  # Other contents omitted
  modules = {
    foo = import ./foo { inherit adios; };
    bar = import ./bar { inherit adios; };
  };
}

