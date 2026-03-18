#!/usr/bin/env bash

QUERY="$*"

python tools/index/search_code.py "$QUERY"
