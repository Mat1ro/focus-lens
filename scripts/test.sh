#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${FOCUS_LENS_BUILD_DIR:-$project_dir/.build}"
developer_dir="$(xcode-select -p)"
cd "$project_dir"
if [[ "$developer_dir" == *CommandLineTools ]]; then
    frameworks="$developer_dir/Library/Developer/Frameworks"
    swift test --disable-xctest --enable-swift-testing --scratch-path "$build_dir" \
        -Xswiftc -F -Xswiftc "$frameworks" \
        -Xlinker -rpath -Xlinker "$frameworks" \
        -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib" "$@"
else
    swift test --scratch-path "$build_dir" "$@"
fi
