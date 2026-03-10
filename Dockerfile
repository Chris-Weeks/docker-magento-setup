# Start from the official OpenLiteSpeed image pre-loaded with PHP 8.2
FROM litespeedtech/openlitespeed:1.7.19-lsphp82

# 1. Install system tools, LiteSpeed's mega-package (common), and build tools for PECL
RUN apt-get update && apt-get install -y \
    wget curl git unzip nano cron mariadb-client build-essential \
    lsphp82-common lsphp82-curl lsphp82-mysql lsphp82-opcache \
    lsphp82-intl lsphp82-redis lsphp82-dev lsphp82-pear \
    nodejs npm \
    && npm install -g grunt-cli

# 2. Build Xdebug & Apply Global PHP Configurations
RUN /usr/local/lsws/lsphp82/bin/pecl install xdebug \
    && find /usr/local/lsws/lsphp82/etc -name "php.ini" -exec sed -i 's/memory_limit = .*/memory_limit = 4G/g' {} \; \
    && find /usr/local/lsws/lsphp82/etc -name "php.ini" -exec sh -c 'echo "zend_extension=xdebug.so" >> "$1"' _ {} \;

# 3. Install Composer and Uncap its Memory Limit
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
ENV COMPOSER_MEMORY_LIMIT=-1

# --- 4. SYNC HOST UID/GID & SET UP HOME DIRECTORY ---
# We accept dynamic variables from docker-compose to prevent root permission locks
ARG UID=1000
ARG GID=1000

# Create a REAL Home Directory so Composer/NPM/Grunt don't crash
RUN mkdir -p /home/nobody && chown -R nobody:nogroup /home/nobody && chmod 777 /home/nobody

# Free up the ID if a default user (like 'ubuntu') is already using it
RUN if getent passwd ${UID} > /dev/null ; then userdel -r $(getent passwd ${UID} | cut -d: -f1) ; fi || true

# Force 'nogroup' and 'nobody' to match host IDs, and assign the new home directory
RUN groupmod -o -g ${GID} nogroup \
 && usermod -o -u ${UID} -g ${GID} -d /home/nobody nobody
# ----------------------------------------------------

# 5. Configure OpenLiteSpeed to point to the Magento pub directory
RUN sed -i 's|vhRoot.*Example/|vhRoot /var/www/html/|g' /usr/local/lsws/conf/httpd_config.conf \
    && sed -i 's|$VH_ROOT/html/|/var/www/html/pub/|g' /usr/local/lsws/conf/templates/*.conf \
    && sed -i 's|$VH_ROOT/html/|/var/www/html/pub/|g' /usr/local/lsws/conf/vhosts/*/vhconf.* \
    && sed -i -E 's/allowSetUID[[:space:]]+0/allowSetUID               1\n  allowOverride           1\n  enableCache             1/g' /usr/local/lsws/conf/vhosts/*/vhconf.*

# 6. Symlink LSPHP to standard PHP command for CLI usage
RUN ln -sf /usr/local/lsws/lsphp82/bin/php /usr/bin/php

# Set working directory
WORKDIR /var/www/html

# Expose standard HTTP/HTTPS and LiteSpeed WebAdmin ports
EXPOSE 80 443 7080
