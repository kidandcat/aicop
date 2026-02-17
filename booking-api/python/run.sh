#!/usr/bin/env bash
export WORKDIR="$(pwd)"
cd "$(dirname "$0")"
pip install -r requirements.txt -q 2>/dev/null
exec python3 server.py
