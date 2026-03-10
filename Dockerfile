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
# We then append the zend_extension and increase the memory_limit directly in LiteSpeed's php.ini
RUN /usr/local/lsws/lsphp82/bin/pecl install xdebug \
    && echo "zend_extension=xdebug.so" >> /usr/local/lsws/lsphp82/etc/php/8.2/php.ini \
    && echo "memory_limit=4G" >> /usr/local/lsws/lsphp82/etc/php/8.2/php.ini

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Fix Permissions First: OpenLiteSpeed uses 'nobody' instead of 'www-data'
# We use the -o flag to allow non-unique IDs in case the base image already uses 1000
RUN usermod -o -u 1000 nobody && groupmod -o -g 1000 nogroup

# Create Composer Home (Outside of /tmp to avoid Docker Volume wipes)
ENV COMPOSER_HOME=/var/composer_home
RUN mkdir -p /var/composer_home && chown -R nobody:nogroup /var/composer_home && chmod 777 /var/composer_home

# 3. Configure OpenLiteSpeed to point to the Magento pub directory and read .htaccess
# We use wildcards (*) so it works whether LiteSpeed named it 'Example', 'localhost', '.conf', or '.xml'
RUN sed -i 's|$VH_ROOT/html/|/var/www/html/pub/|g' /usr/local/lsws/conf/vhosts/*/vhconf.* \
    && sed -i -E 's/allowSetUID[[:space:]]+0/allowSetUID               1\n  allowOverride           1\n  enableCache             1/g' /usr/local/lsws/conf/vhosts/*/vhconf.*

# Symlink LSPHP to standard PHP command for CLI usage
RUN ln -sf /usr/local/lsws/lsphp82/bin/php /usr/bin/php

# Set working directory
WORKDIR /var/www/html

# Expose standard HTTP/HTTPS and LiteSpeed WebAdmin ports
EXPOSE 80 443 7080
