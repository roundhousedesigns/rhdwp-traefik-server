#!/bin/bash
set -e

utilsDir="$( cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd )"
rootDir="$(dirname "${utilsDir}")"
wwwDir="${rootDir}/www"

## Update Traefik stack
echo "UPDATE Traefik"
git -C "$rootDir" checkout master
git -C "$rootDir" pull -q

for d in "$wwwDir"/*; do
  if [ -d "$d" ]; then
    docker_compose="${d}"/docker-compose.yml

    docker-compose -f "$docker_compose" --log-level ERROR run --rm wp-cli plugin update --all
    docker-compose -f "$docker_compose" --log-level ERROR run --rm wp-cli theme update --all
    docker-compose -f "$docker_compose" --log-level ERROR run --rm wp-cli core update
  fi
done
