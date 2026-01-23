FROM php:8.3-cli-alpine

COPY --from=composer /usr/bin/composer /usr/bin/composer

ARG UID=1000
ARG GID=1000
ARG ENVIRONMENT=production
ARG DEBUG=0
ARG UGN
ARG TZ

ENV ENVIRONMENT=${ENVIRONMENT}
ENV DEBUG=${DEBUG}
ENV UGN=${UGN}
ENV UID=${UID}
ENV GID=${GID}
ENV TZ=${TZ:-UTC}

RUN addgroup -g $GID $UGN || true && \
    adduser -D -u $UID -G $UGN $UGN || true

# Настройка таймзоны
RUN ln -snf /usr/share/zoneinfo/${TZ:-UTC} /etc/localtime && echo ${TZ:-UTC} > /etc/timezone

RUN apk add --no-cache \
    bash git tzdata msmtp wget imagemagick linux-headers ca-certificates su-exec fcgi \
    freetds freetype gettext gmp icu-libs imap libffi libintl libjpeg-turbo \
    libpng librdkafka libssh2 libstdc++ libtool libxpm libxslt libzip make \
    rabbitmq-c unixodbc libmemcached-libs libldap lz4-libs zstd-libs antiword libwebp curl

RUN apk add --no-cache --virtual .build-deps \
    autoconf bzip2-dev cmake curl-dev freetds-dev freetype-dev g++ gcc \
    imagemagick-dev gettext-dev gmp-dev icu-dev imap-dev krb5-dev \
    libmemcached-dev libc-dev libjpeg-turbo-dev libpng-dev librdkafka-dev \
    libssh2-dev libwebp-dev libxml2-dev libxpm-dev libxslt-dev libzip-dev \
    openssl-dev pcre-dev pkgconf rabbitmq-c-dev zlib-dev \
    lz4-dev zstd-dev openldap-dev libwebp-dev

# GD
RUN ln -s /usr/lib/$(apk --print-arch)-linux-gnu/libXpm.* /usr/lib/ || true && \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp --with-xpm --enable-gd-jis-conv && \
    docker-php-ext-install -j$(nproc) gd

# Основные модули
RUN docker-php-ext-install -j$(nproc) \
    bcmath bz2 exif gettext gmp intl mysqli opcache pdo_mysql pcntl \
    sockets sysvmsg sysvsem sysvshm xsl zip curl

# Установка PECL-модулей, кроме memcached (он будет собираться отдельно)
RUN pecl channel-update pecl.php.net && \
    pecl install amqp apcu zstd msgpack mongodb redis rdkafka ssh2 igbinary && \
    docker-php-ext-enable amqp apcu zstd msgpack mongodb redis rdkafka ssh2 igbinary

# Сборка memcached с поддержкой igbinary
RUN git clone https://github.com/php-memcached-dev/php-memcached.git /usr/src/php/ext/memcached && \
    cd /usr/src/php/ext/memcached && \
    git checkout v3.3.0 && \
    phpize && \
    ./configure --enable-memcached-igbinary && \
    make -j$(nproc) && \
    make install && \
    echo "extension=memcached.so" > /usr/local/etc/php/conf.d/memcached.ini

# LZ4
RUN git clone https://github.com/kjdev/php-ext-lz4 /opt/lz4 && \
    cd /opt/lz4 && \
    phpize && ./configure --enable-lz4 --with-lz4-includedir=/usr && \
    make -j$(nproc) && make install && docker-php-ext-enable lz4

# Imagick
RUN curl -L -o /tmp/imagick.tar.gz https://github.com/Imagick/imagick/archive/refs/tags/3.7.0.tar.gz && \
    tar -xzf /tmp/imagick.tar.gz -C /tmp && \
    cd /tmp/imagick-* && phpize && ./configure && make && make install && \
    echo "extension=imagick.so" > /usr/local/etc/php/conf.d/ext-imagick.ini

# LDAP
RUN docker-php-ext-configure ldap && docker-php-ext-install ldap

# Mailhog
RUN if [ "$ENVIRONMENT" = "local" ] || [ "$ENVIRONMENT" = "dev" ]; then \
    curl -LkSso /usr/bin/mhsendmail https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64 && \
    chmod 0755 /usr/bin/mhsendmail ; fi

# Xdebug
RUN if [ "$DEBUG" = "1" ] || [ "$DEBUG" = "true" ]; then \
    pecl install xdebug && docker-php-ext-enable xdebug && \
    echo "xdebug.mode=develop,debug" > /usr/local/etc/php/conf.d/xdebug.ini && \
    echo "xdebug.client_host=host.docker.internal" >> /usr/local/etc/php/conf.d/xdebug.ini && \
    echo "xdebug.client_port=9003" >> /usr/local/etc/php/conf.d/xdebug.ini && \
    echo "xdebug.start_with_request=yes" >> /usr/local/etc/php/conf.d/xdebug.ini ; fi

RUN mv $PHP_INI_DIR/php.ini-development $PHP_INI_DIR/php.ini

RUN apk del .build-deps && docker-php-source delete && rm -rf /tmp/* /var/cache/apk/* /opt/lz4

RUN mkdir -p /home/$UGN/app /home/$UGN/tmp && \
    chown -R $UGN:$UGN /home/$UGN/app /home/$UGN/tmp
WORKDIR /home/$UGN/app
USER $UGN