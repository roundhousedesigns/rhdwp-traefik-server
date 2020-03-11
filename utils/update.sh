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
    composeFile="${d}"/docker-compose.yml

    /usr/local/bin/docker-compose -f "$composeFile" --log-level ERROR run --rm wp-cli plugin update --all
    /usr/local/bin/docker-compose -f "$composeFile" --log-level ERROR run --rm wp-cli theme update --all
    /usr/local/bin/docker-compose -f "$composeFile" --log-level ERROR run --rm wp-cli core update
  fi
done
