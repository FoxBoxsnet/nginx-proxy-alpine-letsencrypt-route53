# Test if requirements are met
(
	type docker &>/dev/null || ( echo "docker is not available"; exit 1 )
)>&2


# set a few global variables
SUT_IMAGE=foxboxsnet/nginx-proxy-alpine-letsencrypt:bats
TEST_FILE=$(basename $BATS_TEST_FILENAME .bats)


# load the Bats stdlib (see https://github.com/sstephenson/bats/pull/110)
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
export BATS_LIB="${DIR}/lib/bats"
load "${BATS_LIB}/batslib.bash"


# load additional bats helpers
load ${DIR}/lib/helpers.bash
load ${DIR}/lib/docker_helpers.bash


# Define functions specific to our test suite

# run the SUT docker container 
# and makes sure it remains started
# and displays the nginx-proxy start logs
#
# $1 container name
# $@ other options for the `docker run` command
function nginxproxy {
	local -r container_name=$1
	shift
	docker_clean $container_name \
	&& docker run -d \
		--name $container_name \
		"$@" \
		$SUT_IMAGE \
	&& wait_for_nginxproxy_container_to_start $container_name \
	&& docker logs $container_name
}


# wait until the nginx-proxy container is ready to operate
#
# $1 container name
function wait_for_nginxproxy_container_to_start {
	local -r container_name=$1
	sleep .5s  # give time to eventually fail to initialize

	function is_running {
		run docker_running_state $container_name
		assert_output "true"
	}
	retry 3 1 is_running
}


# Send a HTTP request to container $1 for path $2 and 
# Additional curl options can be passed as $@
#
# $1 container name
# $2 HTTP path to query
# $@ additional options to pass to the curl command
function curl_container {
	local -r container=$1
	local -r path=$2
	shift 2
	docker run --rm appropriate/curl --silent \
		--connect-timeout 5 \
		--max-time 20 \
		"$@" \
		http://$(docker_ip $container)${path}
}


# start a container running (one or multiple) webservers listening on given ports
#
# $1 container name
# $2 container port(s). If multiple ports, provide them as a string: "80 90" with a space as a separator
# $@ `docker run` additional options
function prepare_web_container {
	local -r container_name=$1
	local -r ports=$2
	shift 2
	local -r options="$@"

	local expose_option=""
	IFS=$' \t\n' # See https://github.com/sstephenson/bats/issues/89
	for port in $ports; do
		expose_option="${expose_option}--expose=$port "
	done

	(	# used for debugging purpose. Will be display if test fails
		echo "container_name: $container_name"
		echo "ports: $ports"
		echo "options: $options"
		echo "expose_option: $expose_option"
	)>&2
	
	docker_clean $container_name

	# GIVEN a container exposing 1 webserver on ports 1234
	run docker run -d \
		--label bats-type="web" \
		--name $container_name \
		$expose_option \
		-w /var/www/ \
		$options \
		-e PYTHON_PORTS="$ports" \
		python:3 bash -c "
			trap '[ \${#PIDS[@]} -gt 0 ] && kill -TERM \${PIDS[@]}' TERM
			declare -a PIDS
			for port in \$PYTHON_PORTS; do
				echo starting a web server listening on port \$port;
				mkdir /var/www/\$port
				cd /var/www/\$port
				echo \"answer from port \$port\" > data
				python -m http.server \$port &
				PIDS+=(\$!)
			done
			wait \${PIDS[@]}
			trap - TERM
			wait \${PIDS[@]}
		"
	assert_success

	# THEN querying directly port works
	IFS=$' \t\n' # See https://github.com/sstephenson/bats/issues/89
	for port in $ports; do
		run retry 5 1s docker run --rm appropriate/curl --silent --fail http://$(docker_ip $container_name):$port/data
		assert_output -l 0 "answer from port $port"
	done
}
