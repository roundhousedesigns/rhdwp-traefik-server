#!/bin/bash

## Rebuilds stacks without forcing container recreation (fast)

set -ex

for d in /srv/rhdwp/www/*; do
	dir="${d##*/}"

	echo "UPDATE ${dir}"
	echo "${dir}: Pulling from remote"
	git -C "${d}" pull -q
	
	# Rebuild
	if [[ -f "${d}/build.sh" ]]; then
		( cd "${d}" && ./build.sh -f > /dev/null 2>&1 & )
	fi
done

wait

docker system prune --volumes -f