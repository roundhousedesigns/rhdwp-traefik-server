#!/bin/bash

# Do not process these folders in /srv/www/

docker pull wordpress:latest

for d in /srv/www/*; do
	dir="${d##*/}"

	echo "UPDATE $dir"
	cd "$d" || exit
	echo "$d: Pulling from remote"
	git pull -q
	
	# Rebuild
	bash build.sh -r

	# shuffle salts (bug in docker wordpress)
	# docker-compose run --rm wp-cli config shuffle-salts

	cd /srv/www || exit
done
docker system prune --volumes -f