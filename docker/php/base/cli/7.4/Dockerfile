FROM php:7.4.33-cli-alpine

COPY --from=composer /usr/bin/composer /usr/bin/composer

ARG UID=1000
ARG GID=1000
ARG ENVIRONMENT=production
ARG DEBUG=0
ARG UGN

ENV ENVIRONMENT=${ENVIRONMENT}
ENV DEBUG=${DEBUG}
ENV UGN=${UGN}

RUN addgroup -g $GID $UGN || true && \
    adduser -D -u $UID -G $UGN $UGN || true
# Системные зависимости
RUN apk add --no-cache \
    su-exec \
    bash \
    git \
    tzdata \
    msmtp \
    wget \
    imagemagick \
    linux-headers \
    ca-certificates \
    freetds \
    freetype \
    gettext \
    gmp \
    icu-libs \
    imap \
    libffi \
    libintl \
    libjpeg-turbo \
    libpng \
    librdkafka \
    libssh2 \
    libstdc++ \
    libtool \
    libxpm \
    libxslt \
    libzip \
    make \
    rabbitmq-c \
    unixodbc \
    libmemcached-libs \
    libldap \
    yaml-dev \
    lz4-libs \
    zstd-libs \
    antiword \
    curl \
    libcurl

# Build deps
RUN apk add --no-cache --virtual .build-deps \
    autoconf \
    bzip2-dev \
    cmake \
    curl-dev \
    freetds-dev \
    freetype-dev \
    g++ \
    gcc \
    imagemagick-dev \
    gettext-dev \
    gmp-dev \
    icu-dev \
    imap-dev \
    krb5-dev \
    libmemcached-dev \
    libc-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    librdkafka-dev \
    libssh2-dev \
    libwebp-dev \
    libxml2-dev \
    libxpm-dev \
    libxslt-dev \
    libzip-dev \
    openssl-dev \
    pcre-dev \
    pkgconf \
    rabbitmq-c-dev \
    yaml-dev \
    zlib-dev \
    lz4-dev \
    zstd-dev \
    openldap-dev

# GD
RUN ln -s /usr/lib/$(apk --print-arch)-linux-gnu/libXpm.* /usr/lib/ || true && \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp --with-xpm --enable-gd-jis-conv && \
    docker-php-ext-install -j$(nproc) gd

# Основные PHP модули
RUN docker-php-ext-configure pdo_mysql --with-zlib-dir=/usr && \
    docker-php-ext-install -j$(nproc) \
        bcmath \
        bz2 \
        exif \
        gettext \
        gmp \
        intl \
        mysqli \
        opcache \
        pdo_mysql \
        pcntl \
        sockets \
        sysvmsg \
        sysvsem \
        sysvshm \
        xsl \
        zip \
        curl

# PECL без memcached (он ставится отдельно ниже)
RUN pecl channel-update pecl.php.net && \
    pecl install \
        amqp \
        apcu \
        zstd \
        msgpack \
        mongodb-1.16.2 \
        redis \
        rdkafka \
        ssh2-1.3.1 \
        yaml \
        igbinary && \
    docker-php-ext-enable \
        amqp \
        apcu \
        zstd \
        msgpack \
        mongodb \
        redis \
        rdkafka \
        ssh2 \
        yaml \
        igbinary

# memcached с поддержкой igbinary — вручную через git+phpize
RUN apk add --no-cache \
        libmemcached-dev \
        libevent-dev \
        zlib-dev \
        libressl-dev \
        git \
        libtool \
        autoconf \
        g++ \
        make \
        bash && \
    git clone https://github.com/php-memcached-dev/php-memcached.git /usr/src/php/ext/memcached && \
    cd /usr/src/php/ext/memcached && \
    phpize && \
    ./configure --enable-memcached-igbinary && \
    make -j$(nproc) && \
    make install && \
    echo "extension=memcached.so" > /usr/local/etc/php/conf.d/memcached.ini
    # Установка lz4 из исходников
RUN git clone https://github.com/kjdev/php-ext-lz4 /opt/lz4 && \
    cd /opt/lz4 && \
    git checkout $(git tag | grep -E '^[.0-9]+$' | sort -V | tail -1) && \
    phpize && \
    ./configure --enable-lz4 --with-lz4-includedir=/usr && \
    make -j$(nproc) && \
    make install && \
    docker-php-ext-enable lz4

# Установка imagick
RUN curl -L -o /tmp/imagick.tar.gz https://github.com/Imagick/imagick/archive/refs/tags/3.7.0.tar.gz && \
    tar -xzf /tmp/imagick.tar.gz -C /tmp && \
    cd /tmp/imagick-* && \
    phpize && \
    ./configure && \
    make && \
    make install && \
    echo "extension=imagick.so" > /usr/local/etc/php/conf.d/ext-imagick.ini

# Установка ldap
RUN docker-php-ext-configure ldap && \
    docker-php-ext-install ldap

# Условная установка mhsendmail (если ENVIRONMENT=local)
RUN if [ "$ENVIRONMENT" = "local" ] || [ "$ENVIRONMENT" = "dev" ]; then \
    curl -LkSso /usr/bin/mhsendmail "https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64" && \
    chmod 0755 /usr/bin/mhsendmail ; \
fi

# Условная установка Xdebug (если DEBUG=1 или true)
RUN if [ "$DEBUG" = "1" ] || [ "$DEBUG" = "true" ]; then \
    pecl install xdebug-3.1.5 && \
    docker-php-ext-enable xdebug && \
    echo "xdebug.mode=develop,debug" > /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini && \
    echo "xdebug.client_host=host.docker.internal" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini && \
    echo "xdebug.client_port=9003" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini && \
    echo "xdebug.start_with_request=yes" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini ; \
fi

# Конфиг
RUN mv $PHP_INI_DIR/php.ini-development $PHP_INI_DIR/php.ini

# Очистка
RUN apk del .build-deps && \
    docker-php-source delete && \
    rm -rf /tmp/* /var/cache/apk/* /opt/lz4

RUN mkdir -p /home/${UGN}/app && \
    chown -R ${UGN}:${UGN} /home/${UGN}
WORKDIR /home/${UGN}/app
USER ${UGN}