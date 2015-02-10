#!/bin/bash

if [[ -e /.firstrun ]]; then
    /scripts/first_run.sh
fi

echo "Starting service ..."
/usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
