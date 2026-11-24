# Upstream CUE release binaries with fixed hashes. Used by common.nix (`platformKit.cue.version`).
#
# Add a version: put its four hashes in `knownHashes` (`nix-prefetch-url --type sha256 <url>`, then
# `nix hash convert --hash-algo sha256 --to sri`), or give `platformKit.cue.hashes`.
rec {
  knownHashes = {
    "0.18.0" = {
      "x86_64-linux" = "sha256-b3Y8wgxCF0NE++rXBzdxTWOlDD+n7HEXnmeXTE+cX4E=";
      "aarch64-linux" = "sha256-ILmacIIfNYQTMY2AyVbTYhSqmPYTB68ZEw0xw0kLhFE=";
      "x86_64-darwin" = "sha256-0SLLZxe8a4AkCIKjqFrl02TlSD5XgpwYXVghS9kyBuk=";
      "aarch64-darwin" = "sha256-n4lZqKi+6C2wj6zYkLE48oXAuFC4sYElCGdhwP3tWKU=";
    };
    "0.18.0-rc.4" = {
      "x86_64-linux" = "sha256-CJWN/zgRjnRh5r9onjKf9UfwkCFwEPVokQn7lerLc2Y=";
      "aarch64-linux" = "sha256-PvBhc+QphOOVwC9mZfasZAdn1c48OJ8Nn/tfWBKjz70=";
      "x86_64-darwin" = "sha256-NboL1Mmi/0zmfT8Wu5B0J6t2eFst0nj32pxKlDIdgRs=";
      "aarch64-darwin" = "sha256-ONtaX+ArykjxjWZBcNTi9lV0XpNxG43zDl437XHwT1E=";
    };
  };

  assets = {
    "x86_64-linux" = "linux_amd64";
    "aarch64-linux" = "linux_arm64";
    "x86_64-darwin" = "darwin_amd64";
    "aarch64-darwin" = "darwin_arm64";
  };

  # `version` without the leading v, e.g. "0.18.0".
  mkCue =
    {
      pkgs,
      version,
      hashes ? (
        knownHashes.${version}
          or (throw "platform-kit: no hashes for CUE ${version}; add them to devenv/cue-release.nix or set platformKit.cue.hashes")
      ),
    }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      asset = assets.${system} or (throw "platform-kit: no CUE release asset for ${system}");
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = "cue";
      inherit version;
      src = pkgs.fetchurl {
        url = "https://github.com/cue-lang/cue/releases/download/v${version}/cue_v${version}_${asset}.tar.gz";
        hash = hashes.${system} or (throw "platform-kit: no hash for CUE ${version} on ${system}");
      };
      sourceRoot = ".";
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        install -Dm755 cue "$out/bin/cue"
        runHook postInstall
      '';
      meta = {
        description = "CUE ${version}, upstream release binary";
        homepage = "https://cuelang.org";
        license = pkgs.lib.licenses.asl20;
        mainProgram = "cue";
      };
    };
}
