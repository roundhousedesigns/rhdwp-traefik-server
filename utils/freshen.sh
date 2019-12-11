#!/bin/bash

## Rebuilds stacks without forcing container recreation (fast)

set -e

echo "Checking sudo freshness..."
sudo echo "Done."

for d in /srv/rhdwp/www/*; do
	dir="${d##*/}"

	echo "UPDATE $dir"
	echo "$dir: Pulling from remote"
	git -C "$d" pull -q
	git -C "$d" checkout v2
	
	# Rebuild
	if [[ -f "${d}/build.sh" ]]; then
		( cd "$d" && ./build.sh -r )
	fi
done

docker system prune --volumes -f
