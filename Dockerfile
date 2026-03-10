# Start from the official OpenLiteSpeed image pre-loaded with PHP 8.2
FROM litespeedtech/openlitespeed:1.7.19-lsphp82

# 1. Install system tools, LiteSpeed's mega-package (common), and build tools for PECL
RUN apt-get update && apt-get install -y \
    wget curl git unzip nano cron mariadb-client build-essential \
    lsphp82-common lsphp82-curl lsphp82-mysql lsphp82-opcache \
    lsphp82-intl lsphp82-redis lsphp82-dev lsphp82-pear \
    nodejs npm \
    && npm install -g grunt-cli

# 2. Build Xdebug via PECL (LiteSpeed doesn't provide it via apt on Ubuntu)
# We then append the zend_extension directly to LiteSpeed's php.ini
RUN /usr/local/lsws/lsphp82/bin/pecl install xdebug \
    && echo "zend_extension=xdebug.so" >> /usr/local/lsws/lsphp82/etc/php/8.2/php.ini

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Fix Permissions: OpenLiteSpeed uses 'nobody' instead of 'www-data'
# We use the -o flag to allow non-unique IDs in case the base image already uses 1000
RUN usermod -o -u 1000 nobody && groupmod -o -g 1000 nogroup

# Configure OpenLiteSpeed to point to the Magento pub directory and read .htaccess
# (The Docker image uses 'localhost' instead of 'Example' for its default vhost)
RUN sed -i 's|$VH_ROOT/html/|/var/www/html/pub/|g' /usr/local/lsws/conf/vhosts/localhost/vhconf.xml \
    && sed -i -E 's/allowSetUID[[:space:]]+0/allowSetUID               1\n  allowOverride           1\n  enableCache             1/g' /usr/local/lsws/conf/vhosts/localhost/vhconf.xml

# Symlink LSPHP to standard PHP command for CLI usage
RUN ln -sf /usr/local/lsws/lsphp82/bin/php /usr/bin/php

# Set working directory
WORKDIR /var/www/html

# Expose standard HTTP/HTTPS and LiteSpeed WebAdmin ports
EXPOSE 80 443 7080
