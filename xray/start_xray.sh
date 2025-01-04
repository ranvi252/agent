#!/bin/sh

/usr/bin/xray -c /etc/xray/config.json &

echo $! > /run/xray.pid

sleep 1