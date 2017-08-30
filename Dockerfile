FROM alpine:3.6

ARG VERSION=2.8
LABEL version="${VERSION}" \
	description="php:5.6-alpine with cassandra and kafka support" \
	maintainer="Sébastien RAULT <sebastien@kveer.fr>"

EXPOSE 80

CMD ["/usr/sbin/runit-bootstrap"]

RUN apk update --no-cache && \
	apk upgrade --no-cache && \
	# adding required php modules
	apk add --no-cache \
		nginx \
		nginx-mod-http-headers-more \
		syslog-ng \
		dcron \
		runit \
		php5-cli \
		php5-fpm \
		php5-pdo \
		php5-pdo_mysql \
		php5-curl \
		php5-mcrypt \
		php5-intl \
		php5-zip \
		php5-xsl \
		php5-mysql \
		# for pecl
		php5-openssl && \
	# adding the necessary tools to compile
	apk add --no-cache --virtual .build-deps \
		alpine-sdk \
		php5-dev \
		php5-pear \
		autoconf \
		automake \
		re2c \
		file && \
	# adding some symlink because of some pecl packages
	ln -s php5 /usr/bin/php && \
	ln -s phpize5 /usr/bin/phpize && \
	ln -s php-config5 /usr/bin/php-config && \
	# so pecl has access to the xml extension which is a module
	sed -i "$ s|\-n||g" `which pecl` && \
	pecl update-channels

# installing composer
RUN apk add libressl php5-json php5-phar php5-xml php5-zlib && \
	wget -O /tmp/composer-setup.php https://getcomposer.org/installer && \
	wget -O /tmp/composer-setup.sig https://composer.github.io/installer.sig && \
	# Make sure we're installing what we think we're installing!
	php -r "if (hash('SHA384', file_get_contents('/tmp/composer-setup.php')) !== trim(file_get_contents('/tmp/composer-setup.sig'))) { unlink('/tmp/composer-setup.php'); echo 'Invalid installer' . PHP_EOL; exit(1); }" && \
	php /tmp/composer-setup.php --no-ansi --install-dir=/usr/local/bin --filename=composer --snapshot && \
	rm -f /tmp/composer-setup.*

# adding bower & gulp
RUN apk add --no-cache nodejs-npm && \
	npm install -g bower && \
	npm install -g gulp && \
	npm install -g streamqueue && \
	npm install -g gulp-less gulp-concat gulp-uglify gulp-minify-css gulp-zip

# compile cassandra
# the cassandra pecl v1.3.0+ needs cassandra-cpp-driver 1.7+
RUN apk add --no-cache cassandra-cpp-driver libuv gmp && \
	apk add --no-cahce cassandra-cpp-driver-dev gmp-dev --virtual .build-sec && \
	pecl install cassandra-1.3.0 && \
	apk del .build-sec
	# disable by default
	#echo "extension=cassandra.so" > /etc/php5/conf.d/cassandra.ini

# compile rdkafka
RUN apk add --no-cache librdkafka && \
	apk add --no-cache librdkafka-dev --virtual .build-sec && \
	pecl install rdkafka && \
	echo "extension=rdkafka.so" > /etc/php5/conf.d/rdkafka.ini && \
	apk del .build-sec

# compile memcached
RUN apk add --no-cache libsasl libmemcached-libs zlib && \
	apk add --no-cache cyrus-sasl-dev libmemcached-dev zlib-dev --virtual .build-sec && \
	echo '/usr' > /tmp/c && \
	pecl install memcached-2.2.0 </tmp/c && \
	echo "extension=memcached.so" > /etc/php5/conf.d/memcached.ini && \
	rm /tmp/c && \
	apk del .build-sec

# compile ssh2
RUN apk add --no-cache libssh2 && \
	apk add --no-cache libssh2-dev --virtual .build-sec && \
	pecl install ssh2-0.13 && \
	echo "extension=ssh2.so" > /etc/php5/conf.d/ssh2.ini && \
	apk del .build-sec

RUN adduser -D build && \
	addgroup build abuild && \
	sudo -H -u build mkdir /home/build/thrift && \
	sudo -H -u build mkdir /home/build/php5-pdo_cassandra && \
	sudo -H -u build abuild-keygen -an && \
	source /home/build/.abuild/abuild.conf && \
	cp "$PACKAGER_PRIVKEY".pub /etc/apk/keys/

# compile thrift
COPY APKBUILD-thrift /home/build/thrift/APKBUILD
RUN cd /home/build/thrift && \
	sudo -H -u build abuild -r && \
	apk add --no-cache /home/build/packages/build/x86_64/thrift*.apk && \
	echo "extension=thrift_protocol.so" > /etc/php5/conf.d/thrift_protocol.ini
	
# compile php5-pdo_cassandra
COPY APKBUILD-php5-pdo_cassandra /home/build/php5-pdo_cassandra/APKBUILD
RUN cd /home/build/php5-pdo_cassandra && \
	sudo -H -u build abuild -r && \
	apk add /home/build/packages/build/x86_64/php5-pdo_cassandra-0.6.0-r0.apk && \
	echo "extension=pdo_cassandra.so" > /etc/php5/conf.d/pdo_cassandra.ini

	# cleaning
RUN deluser build && \
	rm -R /home/build && \
	apk del .build-deps

# configuration
COPY services /etc/service
COPY runit-bootstrap /usr/sbin/runit-bootstrap

RUN chmod 755 /usr/sbin/runit-bootstrap && \
	chmod -R 755 /etc/service && \
	rm /etc/nginx/conf.d/default.conf && \
	sed -i -e 's/^;pid/pid/' /etc/php5/php-fpm.conf && \
	sed -i -e 's!^; \?include_path.*!include_path=".:/usr/share/php5"!' /etc/php5/php.ini && \
	# remove the default pool
	sed -i '/^\[www\]/,$d' /etc/php5/php-fpm.conf && \
	# syslog will not access /proc/kmsg inside a docker container
	sed -i '/kmsg/d' /etc/syslog-ng/syslog-ng-source.std && \
	# this will allow us to generate the syslog-ng.conf
	sed -i '1,/^$/c#!/bin/sh' /etc/init.d/syslog-ng && \
	echo -e '\nupdate' >> /etc/init.d/syslog-ng && \
	/etc/init.d/syslog-ng
