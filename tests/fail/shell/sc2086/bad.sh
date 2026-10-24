#!/usr/bin/env bash

# Expected to fail SC2086: $1 is unquoted, so it's subject to word splitting and globbing
echo $1
