#!/bin/sh

if [ -z "$1" ]; then
    echo "Error: Missing required parameter"
    exit 1
fi

/usr/bin/wg-quick up $1 > /var/log/$1.log 2>&1 &

echo $! > /run/$1.pid