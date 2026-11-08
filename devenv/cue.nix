# devenv layer 2 of 3, for repositories with CUE (see base.nix): the CUE binary, the registry for the
# org's modules, `cue fmt` in treefmt.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.platformKit;
  cueRelease = import ./cue-release.nix;
  cue =
    if cfg.cue.version == null then
      pkgs.cue
    else
      cueRelease.mkCue (
        {
          inherit pkgs;
          version = cfg.cue.version;
        }
        // lib.optionalAttrs (cfg.cue.hashes != null) { hashes = cfg.cue.hashes; }
      );
in
{
  imports = [ ./base.nix ];

  options.platformKit.cue = {
    version = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "0.18.0-rc.3";
      example = null;
      description = ''
        The upstream release binary of that CUE version (the modules use language v0.18.0, which
        nixpkgs does not ship yet). null: the CUE of nixpkgs. The version must be listed in
        devenv/cue-release.nix, or give `hashes`.
      '';
    };
    hashes = lib.mkOption {
      type = lib.types.nullOr (lib.types.attrsOf lib.types.str);
      default = null;
      description = "SRI hashes of the release assets per Nix system, for a version not in cue-release.nix.";
    };
  };

  config = {
    packages = [ cue ];

    # Org CUE modules live under ghcr.io/homelab-selfuryon/cue/<repo>, apart from images and
    # manifests (meta/delivery.md). Other modules (cue.dev/...) still come from the central registry.
    env.CUE_REGISTRY = lib.mkDefault ''inline:moduleRegistries: "github.com/homelab-selfuryon": {registry: "ghcr.io/homelab-selfuryon/cue", stripPrefix: true}'';

    treefmt.config.settings.formatter.cue = {
      command = "${cue}/bin/cue";
      options = [ "fmt" ];
      includes = [ "*.cue" ];
      excludes = [ "cue.mod/**" ];
    };
  };
}
