#!/bin/bash

## Rebuilds stacks with --force-recreate

set -e

wd=$(pwd)

for d in /srv/rhdwp/www/*; do
  dir="${d##*/}"

  echo "UPDATE ${dir}"
  echo "${dir}: Pulling from remote"
  git -C "${d}" pull -q

  # Restart
  cd "${d}" && ./buildStack -r && cd "${wd}"
done
docker system prune --volumes -f
