#!/bin/bash
set -e

secrets=./.secrets

## Verify secrets
ask_secrets() {
	# CloudFlare API Key, if not found in secrets
	while [[ -z "${CF_API_KEY}" ]]; do
		read -r -p "CloudFlare API Key: " CF_API_KEY
	done

	# Mailgun API Key, if not found in secrets
	while [[ -z "${MG_API_KEY}" ]]; do
		read -r -p "MailGun API Key: " MG_API_KEY
	done

	# SMTP login for dev mode, if not found in secrets
	while [[ -z "${DEV_SMTP_LOGIN}" ]]; do
		read -r -p "RHDEV SMTP Login (Mailgun): " DEV_SMTP_LOGIN
	done

	# Mailgun API Key, if not found in secrets
	while [[ -z "${DEV_SMTP_PASS}" ]]; do
		read -r -p "RHDEV SMTP Pass (Mailgun): " DEV_SMTP_PASS
	done
	
	# Yeah, I know
	WORDPRESS_SMTP_FROM=postmaster@mail.roundhouse-designs.com
}

## Write to .secrets and lock it down
write_secrets() {
	sudo tee -a "${secrets}" > /dev/null <<-EOT
		CF_API_KEY="${CF_API_KEY}"
		MG_API_KEY="${MG_API_KEY}"
		DEV_SMTP_LOGIN="${DEV_SMTP_LOGIN}"
		DEV_SMTP_PASS="${DEV_SMTP_PASS}"
		WORDPRESS_SMTP_FROM="${WORDPRESS_SMTP_FROM}"
	EOT
	
	sudo chmod 660 "${secrets}" && sudo chgrp www-data "${secrets}"
}

# LetsEncrypt storage
acme=./traefik/acme.json
if [[ ! -f "${acme}" ]]; then
	sudo touch "${acme}"
	sudo chown www-data:www-data "${acme}"
	sudo chmod 600 "${acme}"
fi

# wp-cli permissions
sudo chown -R www-data:www-data ./wp-cli

# Generate secrets
if [[ -r "${secrets}" ]]; then
	# shellcheck disable=SC1091
	# shellcheck source=/srv/rhdwp/.secrets
	source "${secrets}"
else
	ask_secrets
	write_secrets
fi

# Generate traefik.toml
./traefik/gen.sh

# Create sites directory
[[ ! -d ./www ]] && mkdir www

# Start traefik
( cd ./traefik && docker-compose up -d --remove-orphans )
