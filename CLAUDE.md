# platform-kit

The CUE module `github.com/homelab-selfuryon/platform-kit@v0` (`#App` and its render) and the devenv
module every Rust app imports. Part of the `homelab-selfuryon` org; the interface to the other
repositories is `meta/delivery.md` ("App contract", "Cluster-side names"). Change the contract and this
repository in the same session. No Nix flakes: tools come from devenv.

## Layout

```
app/app.cue         #App (schema + render entry), #Render, #Context, #Cluster (cluster-side names)
env/env.cue           environments, sizes, namespace and host patterns
crd/crd.cue           minimal closed schemas: CiliumNetworkPolicy, HTTPRoute, CNPG Cluster, SecretProviderClass
examples/<x>/         apps rendered by the tests
testdata/golden/      expected render of every example and environment
testdata/invalid/     deploy.cue files that cue vet must reject
devenv/base.nix       layer 1, every repo: ripsecrets + detect-private-keys hooks, treefmt (nixfmt, prettier, taplo), linters
devenv/cue.nix        layer 2, repos with CUE: imports base.nix; CUE (platformKit.cue.version), CUE_REGISTRY, cue fmt
devenv/rust-app.nix   layer 3, apps: imports cue.nix; Rust toolchain, postgres option, `devenv test` steps
devenv/cue-release.nix   upstream CUE release binaries with fixed hashes
devenv.yaml/.nix      this repository's own shell and `devenv test` (imports ./devenv/cue.nix; scripts/test.sh + linters)
scripts/test.sh       the CUE tests; scripts/ctx.sh writes a context_gen.cue
```

## Commands

```sh
devenv test                           # what CI runs
devenv shell -- scripts/test.sh       # CUE tests (--update rewrites golden files)
devenv shell -- treefmt               # format
devenv shell -- actionlint && devenv shell -- zizmor --offline .github/workflows
```

## Rules

- CUE language version v0.18.0 (`cue.mod/module.cue`); the devenv CUE is the upstream pre-release
  (`platformKit.cue.version`, default 0.18.0-rc.3). Publishing needs `source: kind: "self"` there.
- `#App` holds the inputs and an optional `context`; its `objects` and `manifestsYAML` (from `#Render`) only
  exist when `context` is present, so `cue vet ./deploy` passes without it. CUE 0.18 pitfalls: a struct may
  not add fields next to an embedded definition (strict embedding), so the render is a comprehension inside
  `#App`; a field `name: name` refers to itself (bind inputs with `let` first); a pattern-constrained
  `env` is closed, merge with comprehensions, not `&`. Lets may not share a name with a field of the same
  struct.
- Typed core kinds come from `cue.dev/x/k8s.io`; CRDs are the closed definitions in `crd/`. Add a
  field there when the render needs it.
- Every change to the render shows in `testdata/golden`: review that diff, it is the PR.
- No `metadata.namespace` on rendered objects. Hardened defaults are not options; an exception would be
  an explicit field in `#Inputs` and an admission decision.
- The three layers are imported by other repositories (`platform-kit/devenv/base.nix`, `cue.nix` or
  `rust-app.nix`, one per repo); a repository'"'"'s own `devenv.nix` must not redefine what they provide.
- The devenv module is a public interface of apps (`devenv.yaml` imports `devenv/rust-app.nix`):
  options (`platformKit.*`) and the steps of `devenv test` are a contract with the reusable workflows.
- Conventional Commits, `!` for breaking changes. Signed commits.
