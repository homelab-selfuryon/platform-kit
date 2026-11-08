# devenv layer 1 of 3, for every platform repository: secret scanning, formatting through treefmt
# (nixfmt, prettier for YAML/JSON/Markdown, taplo for TOML), workflow linters.
#
#   base.nix       every repository with devenv                    (this file)
#   cue.nix        + CUE                                           (imports base.nix)
#   rust-app.nix   + Rust toolchain, Postgres option, app tests    (imports cue.nix)
#
# A repository imports exactly one of them from its devenv.yaml (`platform-kit/devenv/<file>.nix`);
# its own devenv.nix adds only what is specific to it.
{ pkgs, lib, ... }:
{
  config = {
    packages = with pkgs; [
      jq
      actionlint
      zizmor
      shellcheck
    ];

    # One formatter config for the shell (`treefmt`), the git hook and `devenv test`.
    treefmt = {
      enable = true;
      config = {
        programs = {
          nixfmt.enable = true;
          taplo.enable = true;
          prettier = {
            enable = true;
            includes = [
              "*.md"
              "*.yaml"
              "*.yml"
              "*.json"
            ];
            excludes = [
              "devenv.lock"
              "testdata/**"
              "LICENSE"
              "CHANGELOG.md" # written by release-please; formatting it would fight every release
              "release-please-config.json"
              ".release-please-manifest.json"
            ];
          };
        };
      };
    };

    git-hooks.hooks = {
      treefmt.enable = true;
      # Secrets and private keys never reach a public repository.
      ripsecrets.enable = true;
      detect-private-keys.enable = true;
    };

    enterTest = lib.mkBefore ''
      set -euo pipefail
      treefmt --fail-on-change
    '';
  };
}
