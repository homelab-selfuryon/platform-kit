{ ... }:
{
  # Tools and formatting come from devenv/cue.nix (see devenv.yaml): base.nix + CUE.

  # `devenv test` is the CI contract of this repository (base.nix adds `treefmt --fail-on-change`
  # first): the CUE module tests (fmt, vet, every example rendered for every environment, golden
  # files, bad input rejected).
  enterTest = ''
    scripts/test.sh
    actionlint
    zizmor --offline .github/workflows
  '';
}
