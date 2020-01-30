#!/bin/bash
set -e

## Updates restic backup actions, and installs envvars

profile=/home/gaswirth/.profile
b2secrets=/root/.b2secrets
tempSecrets=/tmp/b2secrets

# get secrets
## AFTER RUNNING, THIS GIST WILL BE DELETED AND THIS SCRIPT WILL DIE!
wget -O "$tempSecrets" https://gist.githubusercontent.com/gaswirth/21f27ae2ce934185e2e2699a632bc152/raw/891d61fbf39c2864602055d4c45249a058cb58ae/.tempb2
source "$tempSecrets"

# replace ~/scripts/restic-backup.sh
wget -O /home/gaswirth/scripts/restic-backup.sh https://gist.githubusercontent.com/gaswirth/7adc52eef913c4416797cfc0359ca4e9/raw/3eb07ad2a8cb26347357c7a9782b61725e0fa46c/restic-backup.sh

if ! grep -q 'B2/restic' "$profile"; then
	{
		echo
		echo '# B2/restic'
		echo 'export B2_ACCOUNT_ID='"$B2_ACCOUNT_ID"
		echo 'export B2_ACCOUNT_KEY='"$B2_ACCOUNT_KEY"
		echo 'export RESTIC_PASSWORD_FILE='"$RESTIC_PASSWORD_FILE"
	} >> "$profile"
fi

# Also create a secrets file for cron access
_b2secrets=$(mktemp)
{
	echo "B2_ACCOUNT_ID=${B2_ACCOUNT_ID}"
	echo "B2_ACCOUNT_KEY=${B2_ACCOUNT_KEY}"
	echo "RESTIC_PASSWORD_FILE=$RESTIC_PASSWORD_FILE"
} >> "$_b2secrets"

sudo mv "$_b2secrets" "$b2secrets"
sudo chown root:root "$b2secrets"
sudo chmod 600 "$b2secrets"