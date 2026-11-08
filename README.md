# platform-kit

The paved road of the [homelab-selfuryon](https://github.com/homelab-selfuryon) platform: what a product
team gets as versioned dependencies instead of writing it itself.

1. **CUE module** `github.com/homelab-selfuryon/platform-kit@v0`, published to the GHCR CUE registry on
   `v*` tags.
   - package `app`: `#App`, the schema of an app's `deploy/deploy.cue`, and its render to
     Kubernetes objects with hardened defaults;
   - package `env`: the environments (`preview`, `staging`, `prod`): namespace pattern, host names,
     replicas, sizes, PodDisruptionBudget, database topology;
   - package `crd`: minimal closed schemas of the custom resources that are rendered.
2. **devenv module** (`devenv/rust-app.nix`): the developer shell and CI contract of a Rust app:
   toolchain, CUE, treefmt, git hooks, local Postgres, `devenv test`.

How it fits: [`rust-app-template`](https://github.com/homelab-selfuryon/rust-app-template) uses both (the apps also build their image from their own `Containerfile`);
the reusable workflows in `github-workflows` call `cue export` on an app's `deploy/`; the platform
side (`platform-components`, `gitops`) provides the cluster-side names the render refers to. The
interface is described in `meta/delivery.md` ("App contract", "Cluster-side names").

## The CUE module

```cue
package deploy

import "github.com/homelab-selfuryon/platform-kit/app"

app.#App & {
	name:   "notes-api"
	team:   "notes"
	port:   8080                       // default 8080; the Service listens on 80
	size:   "small"                    // small | medium | large (default small)
	public: true                       // HTTPRoute on the environment's Gateway
	database: postgres: {}             // CloudNativePG cluster, credentials as files
	secrets: ["example-key"]           // OpenBao kv/<team>/<env>/<name>/<key>, files
	env: LOG_LEVEL: "info"             // non-secret config only
	network: {
		allowFrom: [{app: "notes-stats"}]   // may reach this app
		calls: []                               // [{app: "notes-api"}]: egress + token, audience notes-api
		egressFQDN: []                          // [{host: "api.example.org", port: 443}]
		kubeAPI: true                           // egress to the kube-apiserver + a token for it
	}
}
```

Without more, the file is only a schema: `cue vet ./deploy`, `cue export ./deploy -e name --out text` and
`-e team` work. CI writes `deploy/context_gen.cue` (git-ignored) and the render appears:

```cue
package deploy

context: {env: "staging", image: "ghcr.io/homelab-selfuryon/notes-api@sha256:…", version: "v1.2.0", pr?: 12}
```

```sh
cue export ./deploy -e manifestsYAML --out text   # multi-document YAML of that environment
cue export ./deploy -e objects                     # the same as a list (JSON)
scripts/ctx.sh deploy staging                      # writes a context with a dummy digest, for local use
```

`pr` is required for `preview`, `image` must be a digest reference.

### What it renders

| Object                                | When       | Notes                                                                                                                                                                                                                                 |
| ------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ServiceAccount` `<name>`             | always     | no token automount                                                                                                                                                                                                                    |
| `Deployment` `<name>`                 | always     | PSA restricted: non-root 65532, read-only rootfs, drop ALL, seccomp `RuntimeDefault`, no privilege escalation, no service links, image by digest, `/healthz` `/readyz` probes, `/tmp` emptyDir, requests and memory limit from `size` |
| `Service` `<name>`                    | always     | ClusterIP, port 80 → container port                                                                                                                                                                                                   |
| `PodDisruptionBudget`                 | prod       | `minAvailable: 1`                                                                                                                                                                                                                     |
| `HTTPRoute` `<name>`                  | `public`   | parent: Gateway `<env>` in `envoy-gateway-system`, listener `https`                                                                                                                                                                   |
| `CiliumNetworkPolicy` `<name>`        | always     | ingress from the Gateway (public) and `allowFrom`; egress to DNS, `calls`, `egressFQDN`, the database, the kube-apiserver (`kubeAPI`)                                                                                                 |
| `Cluster` `<name>-db` (CloudNativePG) | `database` | 1 instance, storage from `size`, cluster default storage class                                                                                                                                                                        |
| `CiliumNetworkPolicy` `<name>-db`     | `database` | the database pods live in the same default-deny namespace                                                                                                                                                                             |
| `SecretProviderClass` `<name>`        | `secrets`  | provider `openbao`, role `<team>-<env>-<name>`, one object per secret                                                                                                                                                                 |

No object carries `metadata.namespace`: the namespace comes from the delivery object (Argo CD
`destination.namespace`). Labels: `app.kubernetes.io/{name,part-of,managed-by,version}`,
`homelab-selfuryon.github.io/{team,env}` (and `/pr` in preview).

Mount points in the container:

| Path                                       | Content                                                                                |
| ------------------------------------------ | -------------------------------------------------------------------------------------- |
| `/var/run/secrets/app/<key>`               | OpenBao secrets (`secrets`)                                                            |
| `/var/run/secrets/db/`                     | CloudNativePG `<name>-db-app` Secret: `uri`, `username`, `password`, `host`, …         |
| `/var/run/secrets/tokens/<service>/token`  | projected ServiceAccount token, audience `<service>` (`calls`), rotated by the kubelet |
| `/var/run/secrets/kube-api/{token,ca.crt}` | token for the kube-apiserver (its default audience) and the cluster CA (`kubeAPI`)     |

Environment variables set by the platform (a `deploy.cue` `env` entry may not use these names):
`PORT`, `APP_ENV`, `APP_VERSION`; `AUTH_AUDIENCE` (= app name) and `AUTH_ALLOWED_SUBJECTS`
(`system:serviceaccount:<ns>:<service>` of every `allowFrom` entry) when `allowFrom` is not empty;
`<CALLEE>_URL` (`http://<callee>.<namespace>.svc.cluster.local`) for every entry of `calls`.

Environments (`env/env.cue`): preview 1 replica, namespace `<team>-pr-<n>`, host
`<svc>-pr-<n>.preview.<domain>`; staging 1 replica, `<team>-staging`, `<svc>.staging.<domain>`; prod 2
replicas and a PodDisruptionBudget, `<team>-prod`, `<svc>.<domain>`. The domain is the placeholder
`homelab.example`. An app that `calls` another one in `preview` calls the staging instance (there is
no sibling in a preview namespace); the callee's allowlist does not name preview namespaces, so such a
call is refused.

Why the CRDs are in `crd/` and not generated: none of the CUE central registry modules exist for
Cilium, Gateway API, CloudNativePG or the Secrets Store CSI driver, and the generated schemas of the full
CRDs are large and slow to evaluate. The closed definitions list only what the render sets.

## The devenv layers

Three files in `devenv/` are imported by other repositories; each repository imports exactly one:

| File           | Adds                                                                                                                                                                                                        | Imported by                        |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| `base.nix`     | git hooks `ripsecrets`, `detect-private-keys` and treefmt; formatters nixfmt, prettier (YAML, JSON, Markdown), taplo; actionlint, zizmor, shellcheck, jq; the `devenv test` step `treefmt --fail-on-change` | every repository (no CUE, no Rust) |
| `cue.nix`      | imports `base.nix`; CUE (option below), `CUE_REGISTRY` for the org modules, `cue fmt` in treefmt                                                                                                            | repositories with CUE              |
| `rust-app.nix` | imports `cue.nix`; Rust toolchain, Postgres option, the app test steps                                                                                                                                      | apps                               |

A repository's own `devenv.nix` adds only what is specific to it. Details of `rust-app.nix`:

`devenv/rust-app.nix` is the developer environment of every Rust app **and** its CI contract
(no Nix flakes anywhere: images come from a `Containerfile`, tools from devenv). It sets:

- the Rust toolchain from the repository's `rust-toolchain.toml` (rust-overlay), cargo-deny,
  cargo-nextest, sqlx-cli, skopeo, jq, actionlint, zizmor, shellcheck;
- **CUE**: the upstream pre-release binary (default `0.18.0-rc.3`, the modules use language `v0.18.0`);
- **formatting** through devenv's treefmt integration: rustfmt (edition 2024), nixfmt, taplo (TOML) and
  `cue fmt`. Run `treefmt`; the git hook is the same treefmt, clippy (`-D warnings`) is a separate hook;
- **`devenv test`**: `treefmt --fail-on-change`, a check that the `Containerfile` build stage
  (`FROM rust:<version>-…`) names the Rust version of `rust-toolchain.toml`, `cargo clippy -D warnings`,
  `cargo test`, `cargo deny check` (advisories need the network). An app appends its own steps in its
  `devenv.nix` (`enterTest`);
- optionally a local Postgres: `platformKit.postgres.enable = true;` starts `services.postgres` (unix
  socket, trust authentication, database `app`) and the shell exports `DB_URI_FILE` (a file with the
  connection string, the local stand-in for `/var/run/secrets/db/uri`; name configurable with
  `platformKit.postgres.uriFileEnv`) and `DATABASE_URL`.

An app's `devenv.yaml` (devenv modules cannot declare inputs, so the app lists the ones the module
needs next to platform-kit; see `rust-app-template/devenv.yaml`):

```yaml
inputs:
  nixpkgs: { url: "github:cachix/devenv-nixpkgs/rolling" }
  git-hooks:
    {
      url: "github:cachix/git-hooks.nix",
      inputs: { nixpkgs: { follows: nixpkgs } },
    }
  rust-overlay:
    {
      url: "github:oxalica/rust-overlay",
      inputs: { nixpkgs: { follows: nixpkgs } },
    }
  treefmt-nix:
    {
      url: "github:numtide/treefmt-nix",
      inputs: { nixpkgs: { follows: nixpkgs } },
    }
  platform-kit:
    { url: "github:homelab-selfuryon/platform-kit/v0.1.0", flake: false }
imports:
  - platform-kit/devenv/rust-app.nix # or cue.nix / base.nix for repositories without Rust
```

and a `devenv.nix` that can be empty. (Importing a file of an input as `<input>/<path>.nix` works in the
devenv of nixpkgs, 2.4.0; importing a remote `devenv.yaml` needs 2.4.1.) Renovate bumps the `platform-kit`
URL tag; it has no devenv manager for `devenv.lock`, so run `devenv update` (a scheduled workflow is
planned).

### CUE version

`platformKit.cue.version` (default `"0.18.0-rc.3"`) selects the upstream release binary
(`devenv/cue-release.nix`: per-system tarball from the GitHub releases with fixed hashes). `platformKit.cue.version = null;` uses the CUE of nixpkgs. A version that is
not listed needs `platformKit.cue.hashes = { x86_64-linux = "sha256-…"; … };`. The option changes the
tool only; the language version of a module is in its `cue.mod/module.cue`.

## Development

```sh
devenv shell               # cue, jq, treefmt, actionlint, zizmor (devenv.nix imports devenv/cue.nix)
treefmt                    # nixfmt, taplo, cue fmt
scripts/test.sh            # fmt, vet, render every example in every environment, golden files, bad input
scripts/test.sh --update   # rewrite testdata/golden after an intended change
devenv test                # what CI runs: treefmt --fail-on-change, scripts/test.sh, actionlint, zizmor
```

- `examples/<x>/deploy.cue` are rendered for `preview` (pr 12), `staging` and `prod`, compared with
  `testdata/golden/<x>/<env>.yaml`.
- `testdata/invalid/<case>/deploy.cue` must be rejected by `cue vet`.

### Releasing

Tag `vX.Y.Z` (semver; a breaking schema change is `@v1`): `release.yaml` runs the tests and
`cue mod publish` to `ghcr.io/homelab-selfuryon/platform-kit` with the workflow's `GITHUB_TOKEN`. The
package must be public for apps to resolve it without credentials. Consumers resolve with
`CUE_REGISTRY='inline:moduleRegistries: "github.com/homelab-selfuryon": {registry: "ghcr.io/homelab-selfuryon/cue", stripPrefix: true}'` (other modules, `cue.dev/...`, come
from the default registry).

Local end-to-end test without GHCR: `cue mod registry localhost:5077` in the background, then
`CUE_REGISTRY=github.com/homelab-selfuryon=localhost:5077+insecure cue mod publish v0.1.0`; apps
resolve the module with the same `CUE_REGISTRY`.
