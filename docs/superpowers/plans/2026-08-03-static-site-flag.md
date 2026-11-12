# `-N` Static Site Creation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `rhdwpTraefik -N dirname` to clone `roundhousedesigns/rhdwp-static`, write a prompted `.env`, and exit without starting the stack.

**Architecture:** Parallel `newStaticSite()` next to existing `newSite()`. Wire `-N` through `help()` and `getopts`. Reuse the same PROJECT_LABEL sanitization idea as `rhdwpStack` `getProjectLabel` (strip TLD suffix, keep lowercase alnum). Hardcode `CERT_RESOLVER=cloudflare`.

**Tech Stack:** Bash (`rhdwpTraefik`), git clone over SSH, Docker Compose left for the operator.

## Global Constraints

- Scope: `/srv/rhdwp/rhdwpTraefik` only (plus this plan doc).
- Do not modify `newSite()` / `-n`.
- Do not run `docker compose up` or restart Traefik.
- `CERT_RESOLVER` is always `cloudflare` (no prompt).
- Fail if `www/$dirname` already exists.

---

### Task 1: Help text and getopts for `-N`

**Files:**
- Modify: `/srv/rhdwp/rhdwpTraefik` (`help()`, `getopts` string, new `N)` case)

**Interfaces:**
- Produces: `-N` accepted; calls `newStaticSite` (Task 2) then exits

- [x] **Step 1: Update help()**

Update syntax line to include `[-N dirname]` and add:

```bash
echo '  -n dirname    Create a new WordPress site stack'
echo '  -N dirname    Create a new static HTML site stack (rhdwp-static)'
```

(Keep other help lines; clarify `-n` as WordPress.)

- [x] **Step 2: Add getopts case**

Change getopts to `"habcdfkl:m:Mn:N:ps"`.

Add case after `n)`:

```bash
N) # Start a new static site, and exit
	if [[ -z "$OPTARG" ]]; then
		echo "Error: The -N option requires an argument (directory name)."
		exit 1
	else
		echo "Creating static site www/${OPTARG}"
		newStaticSite "${OPTARG}"
		exit 0
	fi
	;;
```

- [x] **Step 3: Verify help lists -N**

Run: `./rhdwpTraefik -h`
Expected: help text includes `-N dirname` and WordPress wording for `-n`.

- [x] **Step 4: Commit** (deferred — commit with Task 2 when requested)

---

### Task 2: Implement `newStaticSite()`

**Files:**
- Modify: `/srv/rhdwp/rhdwpTraefik` (add function after `newSite()`)

**Interfaces:**
- Consumes: `wwwDir` global; `$1` = directory name
- Produces: cloned `www/$dir`, `.env` with `VIRTUAL_HOST`, `PROJECT_LABEL`, `CERT_RESOLVER=cloudflare`

- [x] **Step 1: Add newStaticSite() after newSite()**

```bash
newStaticSite() {
	## Create a new static HTML stack in www/
	# $1: the stack directory name (domain)
	local dir="$1"
	local sitePath="${wwwDir}/${dir}"
	local virtualHost projectLabel defaultLabel
	local certResolver="cloudflare"

	if [[ -z "$dir" ]]; then
		echo "No directory name supplied."
		exit 1
	fi

	if [[ -e "$sitePath" ]]; then
		echo "Error: ${sitePath} already exists."
		exit 1
	fi

	echo "Cloning roundhousedesigns/rhdwp-static into www/${dir}..."
	git clone git@github.com:roundhousedesigns/rhdwp-static "${sitePath}"

	# Same idea as rhdwpStack getProjectLabel: strip final TLD, keep lowercase alnum
	defaultLabel=$(echo "${dir%.*}" | tr -dc '[:alnum:]' | tr '[:upper:]' '[:lower:]')
	[[ -z "$defaultLabel" ]] && defaultLabel="static"

	read -r -p "VIRTUAL_HOST [${dir}]: " virtualHost
	virtualHost="${virtualHost:-$dir}"

	read -r -p "PROJECT_LABEL [${defaultLabel}]: " projectLabel
	projectLabel="${projectLabel:-$defaultLabel}"

	if [[ -f "${sitePath}/.env.example" ]]; then
		cp "${sitePath}/.env.example" "${sitePath}/.env"
		# Ensure keys exist / overwrite values
		if grep -q '^VIRTUAL_HOST=' "${sitePath}/.env"; then
			sed -i -E "s|^VIRTUAL_HOST=.*|VIRTUAL_HOST=${virtualHost}|" "${sitePath}/.env"
		else
			echo "VIRTUAL_HOST=${virtualHost}" >>"${sitePath}/.env"
		fi
		if grep -q '^PROJECT_LABEL=' "${sitePath}/.env"; then
			sed -i -E "s|^PROJECT_LABEL=.*|PROJECT_LABEL=${projectLabel}|" "${sitePath}/.env"
		else
			echo "PROJECT_LABEL=${projectLabel}" >>"${sitePath}/.env"
		fi
		if grep -q '^CERT_RESOLVER=' "${sitePath}/.env"; then
			sed -i -E "s|^CERT_RESOLVER=.*|CERT_RESOLVER=${certResolver}|" "${sitePath}/.env"
		else
			echo "CERT_RESOLVER=${certResolver}" >>"${sitePath}/.env"
		fi
	else
		cat >"${sitePath}/.env" <<EOF
PROJECT_LABEL=${projectLabel}
VIRTUAL_HOST=${virtualHost}
CERT_RESOLVER=${certResolver}
EOF
	fi

	echo
	echo "Static site scaffolded at ${sitePath}"
	echo "Next: cd ${sitePath} && docker compose up -d"
	echo "(Stack not started.)"
}
```

- [x] **Step 2: Manual verify (optional live clone)**

Prefer a throwaway dirname under www/, or verify function presence with:

```bash
bash -n ./rhdwpTraefik
grep -n 'newStaticSite\|N:' ./rhdwpTraefik
```

If cloning: use a disposable name, confirm `.env` has `CERT_RESOLVER=cloudflare`, no `database/`, then remove the test dir.

- [ ] **Step 3: Commit** (awaiting user request)

```bash
git add rhdwpTraefik docs/superpowers/plans/2026-08-03-static-site-flag.md
git commit -m "Add rhdwpTraefik -N static site scaffolding"
```

---

## Spec coverage check

| Spec requirement | Task |
|------------------|------|
| `-N dirname` separate from `-n` | Task 1 |
| Clone `rhdwp-static` | Task 2 |
| No database dirs | Task 2 (omitted) |
| Prompt VIRTUAL_HOST / PROJECT_LABEL | Task 2 |
| Hardcode CERT_RESOLVER | Task 2 |
| Write `.env` / fallback minimal | Task 2 |
| Exit without compose up | Task 1 exit + Task 2 message |
| Abort if path exists | Task 2 |
| Leave `newSite` alone | Both tasks |
