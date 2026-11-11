# A CUE release that nixpkgs does not have (yet): the upstream prebuilt binary with fixed hashes.
# Upstream CUE release binaries with fixed hashes. Used by common.nix (`platformKit.cue.version`).
#
# Add a version: put its four hashes in `knownHashes` (`nix-prefetch-url --type sha256 <url>`, then
# `nix hash convert --hash-algo sha256 --to sri`), or give `platformKit.cue.hashes`.
rec {
  knownHashes = {
    "0.18.0-rc.4" = {
      "x86_64-linux" = "sha256-CJWN/zgRjnRh5r9onjKf9UfwkCFwEPVokQn7lerLc2Y=";
      "aarch64-linux" = "sha256-PvBhc+QphOOVwC9mZfasZAdn1c48OJ8Nn/tfWBKjz70=";
      "x86_64-darwin" = "sha256-NboL1Mmi/0zmfT8Wu5B0J6t2eFst0nj32pxKlDIdgRs=";
      "aarch64-darwin" = "sha256-ONtaX+ArykjxjWZBcNTi9lV0XpNxG43zDl437XHwT1E=";
    };
    "0.18.0-rc.3" = {
      "x86_64-linux" = "sha256-krWMjj9th0vHRt4uve2boMaSRgYfxjYmbbRZ6fL6W50=";
      "aarch64-linux" = "sha256-KRz7DtQhfSEi4i93UNJ6svGn848TPuts+TqIuiLFbsM=";
      "x86_64-darwin" = "sha256-2n3fqRcuusNsFV9kkw4D1+6y9vhWqozcYTvT1Emu5YI=";
      "aarch64-darwin" = "sha256-GQ4UtoKKM02q7QmJ17Eo6A2yAlUj7ADdwfKMlv9IZt4=";
    };
    "0.18.0-rc.1" = {
      "x86_64-linux" = "sha256-ITtBaw8L67DjXgMpiNiHYYf5NczYdzUm1oGb2TRvoQQ=";
      "aarch64-linux" = "sha256-1+a62JOhKb/zgKMqs1qFmfKEXtQHxduupBv2/J8vIu0=";
      "x86_64-darwin" = "sha256-k7yPxUFyb4nPIb5/ewN2o1xrT/mOv3i0ug/h4pJVQ60=";
      "aarch64-darwin" = "sha256-HBIvdaexnA9P+Icagd+SccVYxS8a06nN8BmDF03QA/c=";
    };
  };

  assets = {
    "x86_64-linux" = "linux_amd64";
    "aarch64-linux" = "linux_arm64";
    "x86_64-darwin" = "darwin_amd64";
    "aarch64-darwin" = "darwin_arm64";
  };

  # `version` without the leading v, e.g. "0.18.0-rc.1".
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
