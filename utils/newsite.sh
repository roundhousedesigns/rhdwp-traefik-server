#!/bin/bash
#$1: new site site path

if [ -z "$1" ]; then
    echo "No site path supplied."
    exit 1
else
    sitepath="/srv/rhdwp/www/$1"

    git clone -b traefik-node git@github.com:gaswirth/rhdwp-docker "${sitepath}"
    cd "${sitepath}" || exit

    ./build.sh
fi
