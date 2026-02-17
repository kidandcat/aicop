#!/usr/bin/env bash
export WORKDIR="$(pwd)"
cd "$(dirname "$0")"
# Download cJSON if not present
if [ ! -f cJSON.c ]; then
    curl -sL https://raw.githubusercontent.com/DaveGamble/cJSON/master/cJSON.c -o cJSON.c
    curl -sL https://raw.githubusercontent.com/DaveGamble/cJSON/master/cJSON.h -o cJSON.h
fi
if [ ! -f booking-api ]; then
    make 2>/dev/null
fi
exec ./booking-api
