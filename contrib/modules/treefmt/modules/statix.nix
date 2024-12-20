{ pkgs }:
{
  types,
  lib,
  ...
}:
{
  name = "treefmt-statix";

  options = {
    package = {
      type = types.derivation;
      default = pkgs.statix;
    };

    disabled-lints = {
      type = types.listOf types.string;
      default = [ ];
    };
  };

  impl = options: {
    name = "statix";
    treefmt = {
      command =
        let
          cmd = lib.getExe options.package;

          # statix requires its configuration file to be named statix.toml exactly
          # See: https://github.com/nerdypepper/statix/pull/54
          settingsDir =
            pkgs.runCommandLocal "statix-config"
              {
                nativeBuildInputs = [ pkgs.remarshal ];
                value = builtins.toJSON {
                  disabled = options.disabled-lints;
                };
                passAsFile = [ "value" ];
                preferLocalBuild = true;
              }
              ''
                mkdir "$out"
                json2toml "$valuePath" "''${out}/statix.toml"
              '';

        in
        pkgs.writeShellScript "statix-fix" ''
          for file in "''$@"; do
            ${cmd} fix --config ${settingsDir}/statix.toml "$file"
          done
        '';
      includes = [ "*.nix" ];
    };
  };
}
