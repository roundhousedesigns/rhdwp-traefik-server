#!/bin/bash

for d in /srv/rhdwp/www/*; do
  echo "$d"
  (
    cd "$d" || return
    sed -i.bak -re 's/WORDPRESS_SMTP_FROM_NAME=(.*?)$/WORDPRESS_SMTP_FROM_NAME="\1"/g' ./.env
  )
done
