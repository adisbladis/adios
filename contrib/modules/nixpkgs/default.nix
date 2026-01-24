adios:

{
  name = "nixpkgs";

  options = {
    pkgs = {
      type = adios.types.attrs;
    };
  };
}
