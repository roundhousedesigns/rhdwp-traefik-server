#!/bin/bash
set -e

for d in /srv/rhdwp/www/*; do
  if [ -d "${d}" ]; then
    docker_compose="${d}"/docker-compose.yml

    docker-compose -f "${docker_compose}" --log-level ERROR run --rm wp-cli plugin update --all
    docker-compose -f "${docker_compose}" --log-level ERROR run --rm wp-cli theme update --all
    docker-compose -f "${docker_compose}" --log-level ERROR run --rm wp-cli core update
  fi
done
