{
  adios,
}:
let
  inherit (adios) types;

  self = {
    name = "write-files";

    options = {
      name = {
        type = types.str;
        default = "files";
      };
      files = {
        type = types.attrsOf self.types.file;
      };
      output = {
        type = types.string;
      };
    };

    inputs = {
      "root" = {
        path = "^";
      };
    };

    types =
      let
        inherit (types)
          union
          struct
          string
          optionalAttr
          enum
          bool
          int
          never
          ;
        optionalStr = optionalAttr string;
        optionalInt = optionalAttr int;
        optionalBool = optionalAttr bool;
        optionalNever = optionalAttr never;
      in
      {
        file =
          let
            # Common options
            common = {
              # Base options
              permissions = optionalStr;
              uid = optionalInt;
              gid = optionalInt;
              clobber = optionalBool;

              # Invalid unless otherwise specified
              text = optionalNever;
              source = optionalNever;
              recursive = optionalNever;
            };

            # File install method
            method = optionalAttr (
              enum "method" [
                # Default when no value is passed
                "symlink"
                # Implies creating a mutable file that gets overwritten on activation
                "copy"
              ]
            );
          in
          types.rename "file" (union [
            # File that is written out into the manifest and written to store and then symlinked/written
            # This can be more performant from the Nix evaluation side as it creates fewer derivations
            (struct "file-text" (
              common
              // {
                text = string;
                inherit method;
              }
            ))

            # File that is linked to the exact source path
            (struct "file-source" (
              common
              // {
                source = union [
                  types.derivation
                  types.path
                  string
                ];
                inherit method;
                recursive = optionalBool;
              }
            ))

            # Directory with permissions
            (struct "file-directory" common)
          ]);
      };

    impl =
      { options, inputs }:
      let
        inherit (inputs.root) pkgs;
        inherit (pkgs) lib;

        package = pkgs.stdenv.mkDerivation {
          inherit (options) name;
          nativeBuildInputs = [
            pkgs.python3
          ];
          manifest = {
            inherit (options) files output;
          };
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          __structuredAttrs = true;
          installPhase = ''
            runHook preInstall
            python3 ${./builder.py}
            cat > $out/script <<EOF
            #!${pkgs.execline}/bin/execlineb -P
            ${lib.getExe pkgs.smfh} activate $out/manifest.json
            EOF
            chmod +x $out/script
            runHook postInstall
          '';
        };
      in
      {
        script = "${package}/script";
      };
  };

in
self
