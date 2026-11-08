#!/usr/bin/env bash
# Write deploy/context_gen.cue the way the reusable workflows do.
# usage: ctx.sh <dir> <env> [pr]
set -euo pipefail
dir=$1 env=$2 pr=${3:-}
digest=sha256:0000000000000000000000000000000000000000000000000000000000000000
{
  echo "package deploy"
  echo
  echo "context: {"
  echo "	env:     \"${env}\""
  echo "	image:   \"ghcr.io/homelab-selfuryon/example@${digest}\""
  echo "	version: \"v1.2.0\""
  if [[ -n ${pr} ]]; then echo "	pr:      ${pr}"; fi
  echo "}"
} >"${dir}/context_gen.cue"
