#!/bin/bash -e
## Rebuilds stacks without forcing container recreation (fast)

# Cleanup first
docker system prune --volumes -f

for d in /srv/rhdwp/www/*; do
  dir="${d##*/}"

  echo "UPDATE $dir"
  echo "$dir: Pulling from remote"
  git -C "$d" checkout master
  git -C "$d" pull -q

  # Rebuild
  if [[ -f "${d}/rhdwpStack" ]]; then
    ( cd "$d" && ./rhdwpStack -q )
  fi
done
