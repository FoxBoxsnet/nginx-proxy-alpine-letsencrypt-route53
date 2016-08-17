FROM alpine:3.4

MAINTAINER FoxBoxsnet

# Environment variable
ENV NGINX_VERSION 1.11.3
ENV NGINX_CT_VERSION 1.3.0
ENV HEADERS_MORE_NGINX_MODULE_VERSION 0.30
## nginx-proxy
ENV DOCKER_GEN_VERSION 0.7.3
ENV FOREGO_VERSION v0.16.1
ENV DOCKER_HOST unix:///tmp/docker.sock
## letsencrypt.sh
ENV OPENSSL_VERSION 1.0.2h-r1
## ct-submit
ENV CT_SUBMIT_VERSION 1.1.2

# Install nginx
ENV GPG_KEYS=B0F4253373F8F6F510D42178520A9993A1C052F8
ENV CONFIG="\
		--prefix=/etc/nginx \
		--sbin-path=/usr/sbin/nginx \
		--modules-path=/usr/lib/nginx/modules \
		--conf-path=/etc/nginx/nginx.conf \
		--error-log-path=/var/log/nginx/error.log \
		--http-log-path=/var/log/nginx/access.log \
		--pid-path=/var/run/nginx.pid \
		--lock-path=/var/run/nginx.lock \
		--http-client-body-temp-path=/var/cache/nginx/client_temp \
		--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
		--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
		--http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
		--http-scgi-temp-path=/var/cache/nginx/scgi_temp \
		--user=nginx \
		--group=nginx \
		--with-http_ssl_module \
		--with-http_realip_module \
		--with-http_addition_module \
		--with-http_gunzip_module \
		--with-http_gzip_static_module \
		--with-http_geoip_module=dynamic \
		--with-threads \
		--with-stream \
		--with-stream_ssl_module \
		--with-http_slice_module \
		--with-file-aio \
		--with-http_v2_module \
		--with-ipv6 \
		\
		--add-dynamic-module=./nginx-ct-$NGINX_CT_VERSION \
		--add-dynamic-module=./headers-more-nginx-module-$HEADERS_MORE_NGINX_MODULE_VERSION \
	"

RUN apk update \
	&& addgroup -S nginx \
	&& adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
	&& apk add --no-cache --virtual .build-nginx \
		gcc \
		libc-dev \
		make \
		openssl-dev \
		pcre-dev \
		zlib-dev \
		linux-headers \
		curl \
		gnupg \
		libxslt-dev \
		gd-dev \
		geoip-dev \
		perl-dev \
		ca-certificates \
		libtool \
		autoconf \
		automake \
		git \
		g++ \
		file \
	&& curl -fSL http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o nginx.tar.gz \
	&& curl -fSL http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc  -o nginx.tar.gz.asc \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$GPG_KEYS" \
	&& gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz \
	&& rm -r "$GNUPGHOME" nginx.tar.gz.asc \
	&& mkdir -p /usr/src \
	&& tar -zxC /usr/src -f nginx.tar.gz \
	&& rm nginx.tar.gz \
	&& cd /usr/src/nginx-$NGINX_VERSION \
	\
	# healthcheck Settings
	&& mkdir -p /etc/nginx/vhost.d \
	&& touch /etc/nginx/vhost.d/healthcheck.conf \
	\
	# nginx-ct Module
	# https://github.com/grahamedgecombe/nginx-ct
	&& curl -fSL https://github.com/grahamedgecombe/nginx-ct/archive/v$NGINX_CT_VERSION.tar.gz \
		-o nginx-ct.tar.gz \
	&& tar -zxC ./ -f nginx-ct.tar.gz \
	&& rm nginx-ct.tar.gz \
	\
	# headers-more-nginx-module Module
	# https://github.com/openresty/headers-more-nginx-module
	&& curl -fSL https://github.com/openresty/headers-more-nginx-module/archive/v$HEADERS_MORE_NGINX_MODULE_VERSION.tar.gz \
		-o headers-more-nginx-module.tar.gz \
	&& tar -zxC ./ -f headers-more-nginx-module.tar.gz \
	&& rm headers-more-nginx-module.tar.gz \
	\
	&& cd /usr/src/nginx-$NGINX_VERSION \
	&& ./configure $CONFIG --with-debug \
	&& make \
	&& mv objs/nginx objs/nginx-debug \
	&& mv objs/ngx_http_geoip_module.so objs/ngx_http_geoip_module-debug.so \
	&& ./configure $CONFIG \
	&& make \
	&& make install \
	&& rm -rf /etc/nginx/html/ \
	&& mkdir /etc/nginx/conf.d/ \
	&& mkdir -p /usr/share/nginx/html/ \
	&& install -m644 html/index.html /usr/share/nginx/html/ \
	&& install -m644 html/50x.html /usr/share/nginx/html/ \
	&& install -m755 objs/nginx-debug /usr/sbin/nginx-debug \
	&& install -m755 objs/ngx_http_geoip_module-debug.so /usr/lib/nginx/modules/ngx_http_geoip_module-debug.so \
	&& ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
	&& strip /usr/sbin/nginx* \
	&& strip /usr/lib/nginx/modules/*.so \
	&& rm -rf /usr/src/nginx-$NGINX_VERSION \
	\
	# Bring in gettext so we can get `envsubst`, then throw
	# the rest away. To do this, we need to install `gettext`
	# then move `envsubst` out of the way so `gettext` can
	# be deleted completely, then move `envsubst` back.
	&& apk add --no-cache --virtual .gettext gettext \
	&& mv /usr/bin/envsubst /tmp/ \
	\
	&& runDeps="$( \
		scanelf --needed --nobanner /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
			| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
			| sort -u \
			| xargs -r apk info --installed \
			| sort -u \
	)" \
	&& apk add --no-cache --virtual .nginx-rundeps $runDeps \
	&& apk del .gettext \
	&& mv /tmp/envsubst /usr/bin/ \
	\
	# forward request and error logs to docker log collector
	&& ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log \
	&& apk del .build-nginx

	# nginx-proxy
	# https://github.com/jwilder/forego
	# https://github.com/jwilder/docker-gen
	# Install wget and ca-certificates and bash
RUN apk add --no-cache bash \
	&& apk add --no-cache --virtual .build-nginx-proxy \
		wget \
		curl \
		ca-certificates \
	# Install Forego
	&&curl -L https://github.com/jwilder/forego/releases/download/$FOREGO_VERSION/forego \
		-o /usr/local/bin/forego \
	&& chmod u+x /usr/local/bin/forego \
	\
	# Install docker-gen
	&& mkdir -p /usr/local/temp \
	&& cd /usr/local/temp \
	&& curl -L https://github.com/jwilder/docker-gen/releases/download/0.7.3/docker-gen-alpine-linux-amd64-$DOCKER_GEN_VERSION.tar.gz \
		-o docker-gen-linux-amd64-$DOCKER_GEN_VERSION.tar.gz \
	&& tar -C /usr/local/bin -xvzf docker-gen-linux-amd64-$DOCKER_GEN_VERSION.tar.gz \
	&& rm docker-gen-linux-amd64-$DOCKER_GEN_VERSION.tar.gz \
	&& apk del .build-nginx-proxy

	#ct-submit
	# https://github.com/grahamedgecombe/ct-submit
RUN apk add --no-cache --virtual .build-ct-submit \
		go \
		curl \
		binutils \
		ca-certificates \
	&& mkdir -p /usr/local/temp \
	&& cd /usr/local/temp \
	&& curl -L https://github.com/grahamedgecombe/ct-submit/archive/v$CT_SUBMIT_VERSION.tar.gz \
		-o ct-submit-$CT_SUBMIT_VERSION.tar.gz \
	&& tar -C /usr/local/temp -xvzf ct-submit-$CT_SUBMIT_VERSION.tar.gz \
	&& rm ct-submit-$CT_SUBMIT_VERSION.tar.gz \
	&& cd ./ct-submit-$CT_SUBMIT_VERSION \
	&& go build \
	&& strip ct-submit-$CT_SUBMIT_VERSION \
	&& mv ct-submit-$CT_SUBMIT_VERSION /usr/local/bin/ct-submit \
	&& rm -rf /usr/local/temp \
	&& chmod +x /usr/local/bin/ct-submit \
	&& apk del .build-ct-submit


	# Install letsencrypt.sh
	# https://github.com/lukas2511/letsencrypt.sh
RUN apk add --no-cache \
		curl \
		ca-certificates \
		sed \
		openssl=$OPENSSL_VERSION \
		coreutils \
	&& curl -L https://raw.githubusercontent.com/lukas2511/letsencrypt.sh/master/letsencrypt.sh \
			-o /usr/local/bin/letsencrypt.sh \
	&& chmod +x /usr/local/bin/letsencrypt.sh \
	\
	# letsencrypt-cloudflare-hook
	# https://github.com/kappataumu/letsencrypt-cloudflare-hook
	&& apk add --no-cache \ 
		python \ 
	&& apk add --no-cache --virtual .build-cloudflare \ 
		python-dev \ 
		py-setuptools \ 
		openssl-dev \ 
		libffi-dev \ 
		musl-dev \ 
		py-pip \ 
		gcc \ 
	&& curl -L https://raw.githubusercontent.com/kappataumu/letsencrypt-cloudflare-hook/master/requirements-python-2.txt \ 
		-o requirements-python-2.txt \ 
	&& pip install --no-cache-dir -r requirements-python-2.txt \ 
	&& rm requirements-python-2.txt \ 
	&& curl -L https://raw.githubusercontent.com/kappataumu/letsencrypt-cloudflare-hook/master/hook.py \ 
		-o /usr/local/bin/hook.py \ 
	&& chmod +x /usr/local/bin/hook.py \
	&& apk del .build-cloudflare 



EXPOSE 80 443

COPY nginx.conf /etc/nginx/nginx.conf
COPY docker-entrypoint.sh /app/
COPY letsencrypt/letsencrypt_service letsencrypt/letsencrypt_service_data.tmpl letsencrypt/update_certs letsencrypt/update_nginx nginx.tmpl Procfile /app/

WORKDIR /app/

VOLUME ["/etc/nginx/certs"]

ENTRYPOINT ["/app/docker-entrypoint.sh"]

CMD ["forego", "start", "-r"]