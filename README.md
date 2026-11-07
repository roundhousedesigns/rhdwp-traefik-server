Traefik for the RHDWP Docker stack.
---
Traefik-routed environment with LetsEncrypt support.

- Run `rhdwpStart` to run quick setup and start the main traefik server stack. Also used to rebuild config files, though that's rarely necessary anymore.

- To spin up a new site, use: `./utils/newsite.sh [sitename]` from the `www` directory

## Monitoring

`rhdwpTraefik` starts the `monitoring/` Compose project after Traefik is up and stops it without deleting volumes.

- Grafana is at `https://<host FQDN>` and requires a login. Anonymous access is off. `GRAFANA_ADMIN_USER` (default `admin`) and `GRAFANA_ADMIN_PASSWORD` live in `traefik/.env`. The password is generated the first time that file is written, and Grafana uses it when its data volume is first created.
- Prometheus (`127.0.0.1:9090`), cAdvisor (`127.0.0.1:8083`), and Traefik's Prometheus entrypoint (`127.0.0.1:8082`) listen on localhost only. Retention is 7 days.
