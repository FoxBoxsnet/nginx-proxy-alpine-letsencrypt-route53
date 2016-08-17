#!/bin/bash
set -e

# Warn if the DOCKER_HOST socket does not exist
if [[ $DOCKER_HOST == unix://* ]]; then
	socket_file=${DOCKER_HOST#unix://}
	if ! [ -S $socket_file ]; then
		cat >&2 <<-EOT
			ERROR: you need to share your Docker host socket with a volume at $socket_file
			Typically you should run your foxboxsnet/nginx-proxy-alpine-letsencrypt-cloudflare with: \`-v /var/run/docker.sock:$socket_file:ro\`
			See the documentation at http://git.io/vZaGJ
		EOT
		socketMissing=1
	fi
fi

# Please specify the CloudFlare APIs.
if [ ! -n "$CF_EMAIL" ] ;then
	cat >&2 <<-EOT
		ERROR: Please specify the CloudFlare API CF_EMAIL.
		docker run -d
		...
		-e CF_EMAIL='user@example.com'
		-e CF_KEY='K9uX2HyUjeWg5AhAb'
		...
	EOT
	socketMissing=1
fi
if [ ! -n "$CF_KEY" ];then
	cat >&2 <<-EOT
		ERROR: Please specify the CloudFlare API CF_KEY.
		docker run -d
		...
		-e CF_EMAIL='user@example.com'
		-e CF_KEY='K9uX2HyUjeWg5AhAb'
		...
	EOT
	socketMissing=1
fi

# If the user has run the default command and the socket doesn't exist, fail
if [ "$socketMissing" = 1 -a "$1" = forego -a "$2" = start -a "$3" = '-r' ]; then
	exit 1
fi

exec "$@"