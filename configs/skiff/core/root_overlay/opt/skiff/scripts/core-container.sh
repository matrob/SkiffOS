#!/bin/sh
set -e
set -x
exec 5>&1

info1() {
  echo " --> $1"
}
info2() {
  echo " ==> $1"
}

if [ ! -d "/opt/skiff" ]; then
  echo "Non-skiff system detected, bailing out!"
  exit 1
fi

PERSIST_MNT=/mnt/persist
TARGET_CORE_MNT=/mnt/core
CORE_PERSIST=$PERSIST_MNT/core
SKIFF_DIR=/opt/skiff
COREENV_DIR=$SKIFF_DIR/coreenv
SKIFF_SCRIPTS_DIR=$SKIFF_DIR/scripts

info2 "Verifying skiff/core:latest image is built..."
IMAGES=$(docker images | sed 1d | grep "latest" | cut -d" " -f1 | grep "skiff/core") || true
if [ -z "$IMAGES" ]; then
  info2 "skiff/core:latest not found, attempting to scratch build it at $COREENV_DIR"
  cd $COREENV_DIR
  # Find the FROM definition
  if [ ! -f Dockerfile ]; then
    info2 "Dockerfile not found!"
    exit 1
  fi
  FROM_IMG=$(cat Dockerfile | grep -m1 '^FROM .*$' | sed "s/FROM //") || true
  if [ -z "$FROM_IMG" ]; then
    info1 "Could not find FROM declaration in Dockerfile!"
    exit 1
  fi
  if [ "$FROM_IMG" = "scratch" ]; then
    info1 "Dockerfile is from scratch, skipping scratchbuild."
  else
    FROM_IMG_VERSION=$(echo "$FROM_IMG" | cut -d: -f2)
    FROM_IMG_NOVER=$(echo "$FROM_IMG" | cut -d: -f1)
    if [ -z "$FROM_IMG_VERSION" ]; then
      FROM_IMG_VERSION=latest
    fi
    VER_IMG_VERSION="$(docker images | sed 1d | tr -s ' ' | grep "$FROM_IMG_NOVER" | cut -d" " -f2 | grep -m1 "$FROM_IMG_VERSION")" || true
    info2 "$FROM_IMG scratch building."
    chmod +x $SKIFF_SCRIPTS_DIR/scratchbuild.bash
    IMAGE=$($SKIFF_SCRIPTS_DIR/scratchbuild.bash build $FROM_IMG | tee >(cat - >&5) | tail -n1)
    sed -i -e "s#FROM .*#FROM ${IMAGE}#" Dockerfile
  fi
  info2 "skiff/core:latest copying files."
  cp /usr/bin/dumb-init ./dumb-init
  info2 "skiff/core:latest building."
  docker build -t "skiff/core:latest" .
fi

if CONTAINER_IS_RUNNING=$(docker inspect -f {{.State.Running}} skiff_core); then
  if [ "$CONTAINER_IS_RUNNING" = "true" ]; then
    info2 "Container skiff_core already running, tailing it."
    docker logs -f skiff_core
  else
    info2 "Starting existing container skiff_core..."
    docker start -a skiff_core
  fi
else
  info2 "Starting new skiff core attached..."
  docker run --name=skiff_core -t skiff/core:latest
fi