# Design: `-N` static site creation in rhdwpTraefik

**Date:** 2026-08-03  
**Status:** Approved for implementation planning  
**Scope:** `/srv/rhdwp/rhdwpTraefik` only

## Problem

`rhdwpTraefik -n dirname` always clones the WordPress stack (`roundhousedesigns/rhdwp`) and creates MariaDB data directories. Static HTML sites use a different repository (`roundhousedesigns/rhdwp-static`) and must not get a WordPress/DB layout.

## Decision summary

| Choice | Decision |
|--------|----------|
| CLI shape | Separate flag `-N dirname` (WordPress stays `-n`) |
| Post-clone | Clone + write `.env` with prompted values; do **not** start the stack |
| Cert resolver | Hardcode `CERT_RESOLVER=cloudflare` (no prompt) |
| Implementation style | Parallel `newStaticSite()`; leave `newSite()` unchanged |

## CLI / interface

- Add `N:` to the existing `getopts` string (alongside `n:`).
- Help text documents `-N dirname` as creating a static HTML stack from `roundhousedesigns/rhdwp-static`.
- On `-N`, call `newStaticSite "${OPTARG}"` and **exit** (same control flow as `-n`: no Traefik generate/start path).
- `-n` behavior remains unchanged.

Example:

```bash
./rhdwpTraefik -N example.com
```

## `newStaticSite()` behavior

1. Require a non-empty directory name argument; exit with error if missing.
2. Abort if `www/$dirname` already exists.
3. Clone `git@github.com:roundhousedesigns/rhdwp-static` into `www/$dirname`.
4. Do **not** create `database/` directories.
5. Prompt for:
   - `VIRTUAL_HOST` — default: `dirname`
   - `PROJECT_LABEL` — default: sanitized form of `dirname` suitable for Traefik router names (e.g. strip/replace dots)
6. Always set `CERT_RESOLVER=cloudflare` (no prompt).
7. Write `www/$dirname/.env`:
   - If `.env.example` exists in the clone, copy it and substitute/set the three values above.
   - Otherwise write a minimal `.env` containing those three keys.
8. Print next-step instructions (`cd www/$dirname && docker compose up -d`). Do not run `docker compose up`.

## Error handling

- Fail fast on empty dirname, existing path, or clone failure (script already uses `bash -e`).
- Invalid/missing `-N` argument uses the same style of error messaging as `-n` / `-m`.

## Out of scope

- Starting the static stack or restarting Traefik
- DNS / ACME / Cloudflare record creation
- Changing WordPress `-n` / `newSite()`
- Adding `www` SANs or multi-host Host rules at scaffold time (operators edit compose per static README)
- Changes to the `rhdwp-static` repository itself

## Testing (manual)

1. `./rhdwpTraefik -h` shows `-N`.
2. `./rhdwpTraefik -N test.example.invalid` clones static repo, prompts, writes `.env` with `CERT_RESOLVER=cloudflare`, exits without bringing Traefik up.
3. Re-running the same command fails because the directory exists.
4. `./rhdwpTraefik -n …` still clones `rhdwp` and creates `database/{data,initdb.d}`.
