#!/bin/zsh
# Golden tests: the Swift decoder must match shared/reference/bamboo_reference.py.
set -euo pipefail
cd "${0:A:h}"
mkdir -p ../build
swiftc -O ../BambooDriver/Tablet.swift main.swift -o ../build/golden-decode
../build/golden-decode ../../shared/testdata
