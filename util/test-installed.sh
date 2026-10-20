#!/usr/bin/env bash

set -euo pipefail

rock_tree="$(realpath "${1:?Usage: test-installed.sh <rock-tree> <test-directory>}")"
test_dir="${2:?Usage: test-installed.sh <rock-tree> <test-directory>}"

test -f "$rock_tree/share/lua/5.1/resty/multipart/parser.lua"
mkdir -p "$test_dir/t"
cp t/*.t "$test_dir/t/"
cp -R t/lib "$test_dir/t/"
ln -s "$rock_tree/share/lua/5.1" "$test_dir/lib"
cd "$test_dir"
prove -r t
