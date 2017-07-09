#!/bin/bash -e

NAME="$1"
WHL="$2"
PKG=$(basename "${WHL}" | cut -d'-' -f 1)

unzip $2 > /dev/null

cat > "BUILD" <<EOF
package(default_visibility = ["//visibility:public"])

py_library(
  name = "pkg",
  srcs = glob(["**/*.py"]),
  data = glob(["**/*"], exclude=["**/*.py", "**/* *"]),
  # This makes this directory a top-level in the python import
  # search path for anything that depends on this.
  imports = ["."],
  deps = [
    # TODO(mattmoor): From {name}-{version}.dist-info/metadata.json
  ],
)
EOF

# A convenience for terseness.
mkdir lib
cat > "lib/BUILD" <<EOF
package(default_visibility = ["//visibility:public"])

py_library(
  name = "lib",
  deps = ["//:pkg"],
)
EOF
