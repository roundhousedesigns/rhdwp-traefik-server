Traefik for the RHDWP Docker stack.
---
Traefik-routed environment with LetsEncrypt support.

- Run `rhdwpStart` to run quick setup and start the main traefik server stack. Also used to rebuild config files, though that's rarely necessary anymore.

- To spin up a new site, use: `./utils/newsite.sh [sitename]` from the `www` directory

## Monitoring

`rhdwpTraefik` starts the `monitoring/` Compose project after Traefik is up and stops it without deleting volumes.

- Grafana is at `https://<host FQDN>` and requires a login. Anonymous access is off. `GRAFANA_ADMIN_USER` (default `admin`) and `GRAFANA_ADMIN_PASSWORD` live in `traefik/.env`. The password is generated the first time that file is written and stored in shell quotes, so a restart keeps spaces and quotation marks. Grafana stores that password only on the first database init; the next `rhdwpTraefik` run resets the admin user from the current file, including a password edited after the generated one.
- Provisioned boards: Mission control (the home dashboard), Traffic by site, Errors and latency, Containers, and RHDWP Traefik. They use the Prometheus datasource uid `prometheus`. On startup Grafana drops any older Prometheus datasource and creates that uid again, because a later edit of the uid does not replace the one already stored.
- Prometheus (`127.0.0.1:9090`), cAdvisor (`127.0.0.1:8083`), and Traefik's Prometheus entrypoint (`127.0.0.1:8082`) listen on localhost only. Retention is 7 days.
