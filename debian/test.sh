#!/bin/sh
# This script runs redis server and webdis server and launches the test
# suite. It avoids race condition while obtaining a port to listen by
# binding to random available port. The port is then found via netstat -nlp
# using PID-file.

TMPDIR=`mktemp -d`

WEBDIS_PID=${TMPDIR}/webdis.pid
WEBDIS_CONF=${TMPDIR}/webdis.json

REDIS_CONF=${TMPDIR}/redis.conf
REDIS_PID=${TMPDIR}/redis.pid
REDIS_SOCK=${TMPDIR}/redis.sock

set_up() {
    echo "Generating config files.."
	sed -e "s|REDIS_SOCK|${REDIS_SOCK}|" -e "s|WEBDIS_PID|${WEBDIS_PID}|" \
        debian/webdis-test.json > ${WEBDIS_CONF}
	sed -e "s|REDIS_PID|${REDIS_PID}|" -e "s|REDIS_SOCK|${REDIS_SOCK}|" \
        debian/redis-test.conf > ${REDIS_CONF}

    echo "Starting redis-server.."
	/sbin/start-stop-daemon --start --verbose \
		--pidfile ${REDIS_PID} \
		--exec `which redis-server` -- ${REDIS_CONF} || return 1

    echo "Starting webdis.."
	/sbin/start-stop-daemon --start --verbose \
		--pidfile ${WEBDIS_PID} \
		--exec $PWD/webdis -- ${WEBDIS_CONF} || return 2

    MATCH_STR="`cat $WEBDIS_PID`\\/webdis"
    export WEBDIS_PORT=`netstat -ntlp 2>/dev/null| \
        awk "/$MATCH_STR/ {print \\$4}"|cut -d: -f2`
    [ "$WEBDIS_PORT" -gt 0 ] || return 3
    echo webdis is listening on port "$WEBDIS_PORT"
}

tear_down() {
    echo "Shutting down webdis.."
	/sbin/start-stop-daemon --stop --verbose \
		--retry=TERM/1/KILL/1 \
		--pidfile ${WEBDIS_PID} \
		--name webdis
    echo "Shutting down redis-server.."
	/sbin/start-stop-daemon --stop --verbose \
		--retry=TERM/1/KILL/1 \
		--pidfile ${REDIS_PID} \
		--name redis-server
}

if ! set_up ; then
    echo "Setting up redis/webdis server FAILED."
    tear_down
    exit 1
fi

echo Running test commands: $*

$*
EXIT_CODE=$?

tear_down
rm -fR $TMPDIR

exit $EXIT_CODE
