#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."
probe_dir="$(pwd)/.build/resource-probe"
mkdir -p "$probe_dir"
swiftc -O -swift-version 6 -emit-library -emit-module -module-name MacSyncCore \
  Sources/MacSyncCore/*.swift -o "$probe_dir/libMacSyncCore.dylib" \
  -emit-module-path "$probe_dir/MacSyncCore.swiftmodule"
swiftc -O -swift-version 6 -I "$probe_dir" -L "$probe_dir" -lMacSyncCore \
  Tools/diagnostics/memory-probe.swift -o "$probe_dir/probe" \
  -Xlinker -rpath -Xlinker "$probe_dir"
"$probe_dir/probe" "${1:-1000}"
