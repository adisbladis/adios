# Generated by npins. Do not modify; will be overwritten regularly
let
  data = builtins.fromJSON (builtins.readFile ./sources.json);
  inherit (data) version;

  mkSource =
    spec:
    assert spec ? type;
    let
      path =
        if spec.type == "Git" then
          mkGitSource spec
        else if spec.type == "GitRelease" then
          mkGitSource spec
        else if spec.type == "PyPi" then
          mkPyPiSource spec
        else if spec.type == "Channel" then
          mkChannelSource spec
        else
          builtins.throw "Unknown source type ${spec.type}";
    in
    spec // { outPath = path; };

  mkGitSource =
    {
      repository,
      revision,
      url ? null,
      hash,
      ...
    }:
    assert repository ? type;
    # At the moment, either it is a plain git repository (which has an url), or it is a GitHub/GitLab repository
    # In the latter case, there we will always be an url to the tarball
    if url != null then
      (builtins.fetchTarball {
        inherit url;
        sha256 = hash; # FIXME: check nix version & use SRI hashes
      })
    else
      assert repository.type == "Git";
      let
        urlToName =
          url: rev:
          let
            matched = builtins.match "^.*/([^/]*)(\\.git)?$" repository.url;

            short = builtins.substring 0 7 rev;

            appendShort = if (builtins.match "[a-f0-9]*" rev) != null then "-${short}" else "";
          in
          "${if matched == null then "source" else builtins.head matched}${appendShort}";
        name = urlToName repository.url revision;
      in
      builtins.fetchGit {
        inherit (repository) url;
        rev = revision;
        inherit name;
        # hash = hash;
      };

  mkPyPiSource =
    { url, hash, ... }:
    builtins.fetchurl {
      inherit url;
      sha256 = hash;
    };

  mkChannelSource =
    { url, hash, ... }:
    builtins.fetchTarball {
      inherit url;
      sha256 = hash;
    };
in
if version == 3 then
  builtins.mapAttrs (_: mkSource) data.pins
else
  throw "Unsupported format version ${toString version} in sources.json. Try running `npins upgrade`"
