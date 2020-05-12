#!/bin/bash
## Replacement for WP Cron
##
## todo: make this smarter and check if the stack is running before pinging

# Ping each site in the www/ directory
for d in /srv/rhdwp/www/*; do
  dir="${d##*/}"
  wget -q -O - "https://${dir}/wp-cron.php?doing_wp_cron"
done
