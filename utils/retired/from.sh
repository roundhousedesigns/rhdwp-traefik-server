#!/bin/bash
#set -x
# Do not process these folders in /srv/www/
exclude=(
	'nginx-proxy'
	'portainer'
	'traefik'
)

# Pull any update images
#docker pull --all-tags gaswirth/rhd_wordpress

for d in /srv/www/*; do
	dir="${d##*/}"
	exclude_match=0
	if [ -d "$d" ]; then
		for domain in "${exclude[@]}"; do
			if [ "$domain" = "$dir" ]; then
				exclude_match=1
				echo "SKIP $dir"
				break
			fi
		done
		if [ "$exclude_match" = 0 ]; then
			echo "Processing $dir"
			cd "$d" || exit

			sed -E -i -e "0,/WORDPRESS_SMTP_FROM=(.*?)/s//WORDPRESS_SMTP_FROM_NAME=${dir}/" .env

			cd /srv/www || exit
		fi
	fi
done
