#!/usr/bin/env bash
export WORKDIR="$(pwd)"
cd "$(dirname "$0")"
bundle install --quiet 2>/dev/null
exec ruby server.rb
