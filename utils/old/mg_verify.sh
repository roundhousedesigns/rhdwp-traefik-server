#!/bin/bash

source "/home/gaswirth/.rhdwp-docker"

# Do not process these folders in /srv/www/
exclude=(
        'nginx-proxy'
        'portainer'
        'traefik'
)

for d in /srv/www/*; do
	virtual_host=${d##*/}
	exclude_match=0
	if [ -d "$d" ]; then
		for domain in "${exclude[@]}"; do
			if [ "$domain" = "${virtual_host}" ]; then
				exclude_match=1
				echo "SKIP ${virtual_host}"
				break
			fi
		done
		if [ "$exclude_match" = 0 ]; then
			echo "Processing $virtual_host"
			# Check for saved CLOUDFLARE_API_KEY and MAILGUN_API_KEY
			if [ -r "/home/gaswirth/.rhdwp-docker" ]; then
				source "/home/gaswirth/.rhdwp-docker"
			fi
			
			curl -s --user "api:${MAILGUN_API_KEY}" -X PUT "https://api.mailgun.net/v3/domains/mail.${virtual_host}/verify"
			sleep 2
		fi
	fi
done
