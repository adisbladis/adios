adios:
{
  modules = {
    hello = import ./hello.nix { inherit adios; };
    nixpkgs = import ./nixpkgs.nix { inherit adios; };
  };
}
