#!/usr/bin/env bash
export WORKDIR="$(pwd)"
cd "$(dirname "$0")"
julia --project=. -e 'using Pkg; Pkg.instantiate()' 2>/dev/null
exec julia --project=. server.jl
