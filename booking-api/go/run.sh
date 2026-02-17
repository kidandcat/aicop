#!/usr/bin/env bash
export WORKDIR="$(pwd)"
cd "$(dirname "$0")"
exec go run main.go
