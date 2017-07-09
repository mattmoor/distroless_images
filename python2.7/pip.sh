#!/bin/bash -e

NAME="$1"
REQUIREMENTS_TXT="$2"
REQUIREMENTS_BZL="$3"
REPOSITORY_DIR="$4"

pip wheel -w "${REPOSITORY_DIR}" -r "${REQUIREMENTS_TXT}"

PACKAGES=$(find "${REPOSITORY_DIR}" -type f -name "*.whl")

function package_name() {
  local whl="$1"
  echo ${whl} | cut -d'-' -f 1
}

function install_whl() {
  local whl="$1"
  cat <<EOF
  whl_library(
    name = "${NAME}_$(package_name ${whl})",
    whl = "@${NAME}//:${whl}",
  )

EOF
}

cat > "${REQUIREMENTS_BZL}" <<EOF
"""Install pip requirements.

Generated from ${REQUIREMENTS_TXT}
"""

load("@distroless_images//python2.7:whl.bzl", "whl_library")

def pip_install():
$(for p in ${PACKAGES}; do
  install_whl "$(basename ${p})"
done)

packages = {
$(for p in ${PACKAGES}; do
  echo "\"$(package_name $(basename ${p}))\": \"@${NAME}_$(package_name $(basename ${p}))//lib\","
done)
}
EOF
