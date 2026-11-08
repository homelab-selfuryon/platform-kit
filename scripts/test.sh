#!/usr/bin/env bash
# Tests of the CUE module: vet, render every example for every environment and
# compare with testdata/golden, check that bad input is rejected.
#
#   scripts/test.sh            run
#   scripts/test.sh --update   rewrite testdata/golden
#
# Needs cue and jq (devenv shell).
set -euo pipefail
cd "$(dirname "$0")/.."

update=false
[[ ${1:-} == --update ]] && update=true

fail=0
rm -f examples/*/context_gen.cue testdata/invalid/*/context_gen.cue
trap 'rm -f examples/*/context_gen.cue testdata/invalid/*/context_gen.cue' EXIT

echo "== cue fmt"
cue fmt --check ./... || fail=1

echo "== cue vet"
cue vet ./app ./env ./crd ./examples/...

echo "== examples"
for dir in examples/*/; do
  ex=$(basename "$dir")
  # Without a context: name and team are readable, as the workflows need.
  cue export "./examples/${ex}" -e name --out text >/dev/null
  cue export "./examples/${ex}" -e team --out text >/dev/null
  for env in preview staging prod; do
    pr=""; [[ $env == preview ]] && pr=12
    scripts/ctx.sh "examples/${ex}" "$env" $pr
    out=$(cue export "./examples/${ex}" -e manifestsYAML --out text)
    golden="testdata/golden/${ex}/${env}.yaml"
    if $update; then
      mkdir -p "$(dirname "$golden")"
      printf '%s\n' "$out" >"$golden"
    elif ! diff -u "$golden" <(printf '%s\n' "$out"); then
      echo "FAIL: ${ex}/${env} differs from ${golden}"; fail=1
    fi
    # Invariants, whatever the golden files say.
    objs=$(cue export "./examples/${ex}" -e objects --out json)
    if jq -e 'any(.[]; .metadata.namespace != null)' <<<"$objs" >/dev/null; then
      echo "FAIL: ${ex}/${env}: an object has metadata.namespace"; fail=1
    fi
    if ! jq -e '[.[] | select(.kind == "Deployment")][0].spec.template.spec
        | .automountServiceAccountToken == false
        and .securityContext.runAsNonRoot == true
        and (.containers | all(.securityContext.readOnlyRootFilesystem == true
          and .securityContext.allowPrivilegeEscalation == false
          and .securityContext.capabilities.drop == ["ALL"]
          and (.image | test("@sha256:[a-f0-9]{64}$"))))' <<<"$objs" >/dev/null; then
      echo "FAIL: ${ex}/${env}: Deployment is not hardened"; fail=1
    fi
    pdb=$(jq '[.[] | select(.kind == "PodDisruptionBudget")] | length' <<<"$objs")
    if [[ $env == prod && $pdb != 1 ]] || [[ $env != prod && $pdb != 0 ]]; then
      echo "FAIL: ${ex}/${env}: PodDisruptionBudget count ${pdb}"; fail=1
    fi
  done
done

echo "== invalid input is rejected (cue vet, no context)"
for dir in testdata/invalid/*/; do
  case=$(basename "$dir")
  if cue vet "./testdata/invalid/${case}" >/dev/null 2>&1; then
    echo "FAIL: testdata/invalid/${case} was accepted"; fail=1
  fi
done

echo "== bad context is rejected"
scripts/ctx.sh examples/minimal preview     # preview without a pull request number
if cue export ./examples/minimal -e manifestsYAML --out text >/dev/null 2>&1; then
  echo "FAIL: preview without pr was accepted"; fail=1
fi
sed -i 's/@sha256:[0-9a-f]*/:latest/' examples/minimal/context_gen.cue
if cue export ./examples/minimal -e manifestsYAML --out text >/dev/null 2>&1; then
  echo "FAIL: image without a digest was accepted"; fail=1
fi

if [[ $fail != 0 ]]; then echo "FAILED"; exit 1; fi
echo "OK"
