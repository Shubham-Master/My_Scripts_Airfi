#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $(basename $0) <port>"
    exit 1
fi

PORT=$1
TIMEOUT=2
HOST="portquiz.net"

timeout $TIMEOUT nc -z -w $TIMEOUT $HOST $PORT &>/dev/null

if [ $? -eq 0 ]; then
    echo "Port $PORT is open"
else
    echo "Port $PORT is closed"
fi
