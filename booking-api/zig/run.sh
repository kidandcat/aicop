#!/usr/bin/env bash
export WORKDIR="$(pwd)"
cd "$(dirname "$0")"
if [ ! -f zig-out/bin/booking-api ]; then
    zig build -Doptimize=ReleaseFast 2>/dev/null
fi
exec ./zig-out/bin/booking-api
