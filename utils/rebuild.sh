#!/bin/bash -e

## Rebuilds stacks with --force-recreate

echo "Checking sudo freshness..."
sudo echo "Done."

wd=$(pwd)

for d in /srv/rhdwp/www/*; do
  dir="${d##*/}"

  echo "UPDATE ${dir}"
  echo "${dir}: Pulling from remote"
  git -C "${d}" pull -q

  # Restart
  cd "${d}" && ./rhdwpStack -r && cd "${wd}"
done
docker system prune --volumes -f
