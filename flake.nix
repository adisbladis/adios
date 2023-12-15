{
  description = "A simple & fast Nix type system implemented in Nix";

  outputs = { self, nixpkgs }: (
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
    in
    {
      libTests = import ./tests.nix { inherit lib; };
      lib = let
        types = import ./default.nix { inherit lib; };
      in types // {
        inherit types;
      };

      devShells =
        forAllSystems
        (
          system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          {
            default = pkgs.callPackage ./shell.nix { };
          }
        );
    }
  );
}
