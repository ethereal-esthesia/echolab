#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
STEPS="${1:-50000000}"

echo "Building..."
clang++ -O3 -std=c++20 -march=native -o bench_cpp bench.cpp
rustc -C opt-level=3 -C target-cpu=native -o bench_rust bench.rs

echo "Running with steps=${STEPS}"
./bench_cpp "${STEPS}"
./bench_rust "${STEPS}"
