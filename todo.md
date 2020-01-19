RHDWP Traefik Server TODO
===
- Check if git pull is necessary before running, and 
	- Command: $(git rev-parse HEAD) == $(git rev-parse @{u}))

disable_wp_cron
---
- set cronjob to ping each domain in www/ folder
	- if already exists, update
- add to startTraefik script
	- check for wp server cron job (wget) and add if necessary
	
- create STOP script
	- cleanup:
		- remove wp cron job