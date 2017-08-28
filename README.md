# docker-php-fpm

An alpine-based Docker image to containerize a web PHP application with the support for Cassandra and Kafka.

# Warning

This docker is totally useless in itself. It only serve as a base upon which you can build Docker containers.

# Version

* Alpine 3.6
* PHP 5.6
* nginx 1.12

# Provided PHP extensions

* ssh2 0.13
* rdkafka
* memcached 2.2.0
* cassandra 1.3.0 (disabled by default)
* thrift_protocol
* PDO cassandra

# What's missing

* a nginx vhost
* a php-fpm configuration
* the web site