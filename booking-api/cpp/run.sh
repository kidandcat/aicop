#!/usr/bin/env bash
export WORKDIR="$(pwd)"
cd "$(dirname "$0")"
if [ ! -f build/booking-api ]; then
    cmake -B build -DCMAKE_BUILD_TYPE=Release 2>/dev/null
    cmake --build build -j$(nproc 2>/dev/null || sysctl -n hw.ncpu) 2>/dev/null
fi
exec ./build/booking-api
