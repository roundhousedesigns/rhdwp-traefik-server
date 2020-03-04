#!/bin/bash -e

# Pull any update images
# docker pull wordpress:latest

for d in /srv/rhdwp/www/*; do
	echo "Processing ${d}}"
	(
		cd "${d}" || exit

		# DO STUFF LIKE...
		# docker-compose run --rm wp-cli rewrite flush --hard
		env="${d}/.env"
		#shellcheck disable=SC1090
		source "$env"
		if [[ "$VIRTUAL_HOST" && "$DEV_MODE" != true ]]; then
			email="postmaster@${VIRTUAL_HOST}"
		else
			email="postmaster@mail.roundhouse-designs.com"
		fi

		sed -i "s/WORDPRESS_SMTP_FROM=.*/WORDPRESS_SMTP_FROM=${email}/" "$env"
	)
done
