.SILENT :
.PHONY : test

update-dependencies:
	docker pull jwilder/docker-gen:latest
	docker pull nginx:latest
	docker pull python:3
	docker pull rancher/socat-docker:latest
	docker pull appropriate/curl:latest
	docker pull docker:1.9.1

test:
	docker build -t foxboxsnet/nginx-proxy-alpine-letsencrypt-cloudflare:bats .
	bats test

test-clean:
	./test/cleanup_test_containers.sh
