#!/bin/bash

# Pull any update images
# docker pull wordpress:latest

for d in /srv/www/*; do
	echo "Processing $dir"
	cd "$d" || exit

	# DO STUFF LIKE...
	# docker-compose up -d --remove-orphans

	cd /srv/www || exit
done
