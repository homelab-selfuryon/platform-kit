# devenv module for a Rust app of the platform. It is the developer shell AND the CI contract:
# `devenv test` runs the checks, `devenv shell -- <cmd>` runs anything in the same environment.
#
# Rust toolchain from rust-toolchain.toml, cue, cargo-deny, sqlx-cli, treefmt (rustfmt, nixfmt, taplo,
# cue fmt), clippy as a git hook, an optional local Postgres. `devenv test` runs, in order:
#   treefmt --fail-on-change, the toolchain/Containerfile version check, clippy -D warnings,
#   cargo test, cargo deny check (advisories need the network).
#
# The app's devenv.yaml imports it. devenv modules cannot declare inputs, so the app declares
# the ones the module needs (nixpkgs, git-hooks, rust-overlay, treefmt-nix) next to platform-kit; see
# rust-app-template/devenv.yaml. In devenv.nix:
#   platformKit.postgres.enable = true;   # local Postgres, DB_URI_FILE and DATABASE_URL exported
#   platformKit.cue.version = null;   # nixpkgs CUE instead of the default pre-release (rc.4)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.platformKit;
in
{
  imports = [ ./cue.nix ];

  options.platformKit.postgres = {
    enable = lib.mkEnableOption "a local Postgres for the app (services.postgres), reached over its unix socket";
    database = lib.mkOption {
      type = lib.types.str;
      default = "app";
      description = "Name of the database that is created.";
    };
    uriFileEnv = lib.mkOption {
      type = lib.types.str;
      default = "DB_URI_FILE";
      description = ''
        Environment variable that holds the path of a file with the connection string, the local
        stand-in for /var/run/secrets/db/uri. `DATABASE_URL` (used by tests) is set as well.
      '';
    };
  };

  config = lib.mkMerge [
    {
      # Toolchain from the repository's rust-toolchain.toml.
      languages.rust = {
        enable = true;
        toolchainFile = lib.mkDefault (config.devenv.root + "/rust-toolchain.toml");
      };

      packages = with pkgs; [
        cargo-deny
        cargo-nextest
        sqlx-cli
        skopeo
      ];

      treefmt.config.programs.rustfmt = {
        enable = true;
        edition = "2024";
      };

      git-hooks.hooks.clippy = {
        enable = true;
        settings.denyWarnings = true;
      };

      # The CI contract. Apps append their own steps (e.g. database tests).
      enterTest = lib.mkBefore ''
        set -euo pipefail

        # The Containerfile builds with the toolchain rust-toolchain.toml names.
        toolchain=$(sed -n 's/^channel *= *"\(.*\)"/\1/p' rust-toolchain.toml)
        image=$(sed -n 's/^FROM rust:\([0-9][0-9.]*\)-.*/\1/p' Containerfile | head -1)
        if [ -z "$toolchain" ] || [ "$toolchain" != "$image" ]; then
          echo "rust-toolchain.toml says '$toolchain', the Containerfile build stage says '$image'" >&2
          exit 1
        fi

        cargo clippy --all-targets --locked -- --deny warnings
        cargo test --locked
        cargo deny check
      '';
    }

    (lib.mkIf cfg.postgres.enable {
      services.postgres = {
        enable = true;
        initialDatabases = [ { name = cfg.postgres.database; } ];
      };

      env.${cfg.postgres.uriFileEnv} = "${config.devenv.state}/db/uri";

      # The unix socket lives in the runtime directory; write the URI file when the shell starts, and
      # DATABASE_URL for the tests. Local trust authentication: no password.
      enterShell = ''
        mkdir -p "$DEVENV_STATE/db"
        uri="postgresql://''${USER:-postgres}@localhost/${cfg.postgres.database}?host=$DEVENV_RUNTIME/postgres"
        printf '%s\n' "$uri" > "$DEVENV_STATE/db/uri"
        export DATABASE_URL="$uri"
      '';
    })
  ];
}
