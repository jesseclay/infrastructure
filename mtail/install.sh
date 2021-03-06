#!/usr/bin/env bash

set -e

target="/opt/mtail"

running=0
rebuild=0
restart=0

ref=$(lookup mtail_ref)
actual_ref=$(docker ps --format '{{.Image}}' | grep "mtail:" | cut -d':' -f2 || true)

if [ ! -z "$actual_ref" ]; then
  running=1
fi

if [ "$ref" != "$actual_ref" ]; then
  restart=1
fi

if [ -z "$(docker images -q mtail:$ref)" ]; then
  rebuild=1
fi

if [ ! -z "$(git diff "$target/Dockerfile" "Dockerfile" 2>&1 || echo "new")" ]; then
  echo "mtail dockerfile changed"
  rebuild=1
  restart=1
fi

if [ ! -z "$(git diff "$target/docker.opts" "docker.opts" 2>&1 || echo "new")" ]; then
  echo "mtail docker.opts changed"
  restart=1
fi

if [ ! -z "$(git diff "$target/progs/nginx.mtail" "progs/nginx.mtail" 2>&1 || echo "new")" ]; then
  echo "mtail nginx.mtail changed"
  restart=1
fi

if [ "rebuild$rebuild" == "rebuild1" ]; then
  echo "mtail rebuilding"
  mkdir -p src/
  git clone -q $(lookup mtail_git) "src/mtail"
  git --work-tree="src/mtail" --git-dir="src/mtail/.git" reset -q --hard "$ref"
  cp Dockerfile "src/mtail"
  docker build -t "mtail:$ref" "src/mtail" >/dev/null
  echo "mtail docker image changed"
fi

mkdir -p "$target/logs" "$target/progs"
cp "progs/nginx.mtail" "$target/progs/nginx.mtail"
# XXX workaround until mtail can properly reload programs
restart=1

if [ "restart$restart" == "restart1" ]; then
  echo "mtail restarting"
  if [ "running$running" == "running1" ]; then
    docker stop "mtail" >/dev/null || true
    docker rm -f "mtail" >/dev/null || true
  fi
  docker run $(cat docker.opts) >/dev/null
elif [ "running$running" == "running0" ]; then
  echo "mtail starting"
  docker run $(cat docker.opts) >/dev/null
fi

# we only install these so we can get a diff and rebuild/restart if needed
cp -a "docker.opts" "$target/docker.opts"
cp -a "Dockerfile" "$target/Dockerfile"
