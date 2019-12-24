#!/bin/bash
#$1: Directory name for new site stack

if [ -z "$1" ]; then
    echo "No directory name supplied."
    exit 1
fi

sitepath="/srv/rhdwp/www/$1"
git clone git@github.com:gaswirth/rhdwp-docker "${sitepath}"
cd "${sitepath}" || exit

./buildStack
