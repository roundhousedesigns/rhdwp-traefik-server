#!/bin/bash

# Pull any update images
# docker pull wordpress:latest

for d in /srv/rhdwp/www/*; do
	echo "Processing ${d}}"
	cd "${d}" || exit

	# DO STUFF LIKE...
	# docker-compose run --rm wp-cli rewrite flush --hard
	docker-compose up -d

	cd /srv/rhdwp/www || exit
done
