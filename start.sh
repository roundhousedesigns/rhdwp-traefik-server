#!/bin/bash
# Sets up and (re)starts the main traefik server stack. Also used to rebuild config files.
# options:
#		-f : Run docker-compose up with --force-recreate flag

set -e

## Verify .env
ask_env() {
	# CloudFlare account email
	while [[ -z "$CF_API_EMAIL" ]]; do
		read -r -p "CloudFlare account email: " CF_API_EMAIL
	done
	
	# CloudFlare API Key
	while [[ -z "$CF_API_KEY" ]]; do
		read -r -p "CloudFlare API Key: " CF_API_KEY
	done

	# Mailgun API Key
	while [[ -z "$MG_API_KEY" ]]; do
		read -r -p "MailGun API Key: " MG_API_KEY
	done

	# SMTP login for dev mode
	while [[ -z "$DEV_SMTP_LOGIN" ]]; do
		read -r -p "RHDEV SMTP Login (Mailgun): " DEV_SMTP_LOGIN
	done

	# Mailgun API Key
	while [[ -z "$DEV_SMTP_PASS" ]]; do
		read -r -p "RHDEV SMTP Pass (Mailgun): " DEV_SMTP_PASS
	done
	
	# Yeah, I know
	# SMTP login for dev mode
	while [[ -z "$DEV_SMTP_FROM" ]]; do
		read -r -p "RHDEV SMTP From: " DEV_SMTP_FROM
	done
}

## Write to .env and lock it down
write_env() {
	cat <<-EOT > "$env_file"
		FQDN=$(hostname -f)
		CF_API_EMAIL=$CF_API_EMAIL
		CF_API_KEY=$CF_API_KEY
		MG_API_KEY=$MG_API_KEY
		DEV_SMTP_FROM=$DEV_SMTP_FROM
		DEV_SMTP_LOGIN=$DEV_SMTP_LOGIN
		DEV_SMTP_PASS=$DEV_SMTP_PASS
		DEV_SMTP_FROM=$DEV_SMTP_FROM
	EOT

	sudo chown "$USER" "$env_file"
	sudo chmod 600 "$env_file"
}

## Set up CloudFlare email env var
while getopts "f" opt; do
	case "$opt" in
		f)
			echo "Using --force-recreate..."
			flags='--force-recreate'
			;;
		
		\?)
			echo "Invalid option: -$OPTARG" >&2
			exit 1
			;;
	esac
done

# LetsEncrypt storage
acme=./traefik/acme.json
if [[ ! -f "$acme" ]]; then
	sudo touch "$acme"
	sudo chown www-data:www-data "$acme"
	sudo chmod 600 "$acme"
fi

# wp-cli permissions
sudo chown -R www-data:www-data ./wp-cli

# Generate environment variables
env_file=./traefik/.env
if [[ -r "$env_file" ]]; then
	# shellcheck disable=SC1091
	# shellcheck source=/srv/rhdwp/traefik/.env
	. "$env_file"
fi
ask_env
write_env

# Create sites directory
[[ ! -d ./www ]] && mkdir www

# Shiny new log (or not)
if [[ ! -d ./log ]]; then
	mkdir log
fi
if [[ ! -f ./log/error.log ]]; then
	touch error.log
fi

# Create web network
docker network create web || true

# Start traefik
( cd ./traefik && ( docker-compose down || true ) && docker-compose up -d --remove-orphans ${flags:-} )
