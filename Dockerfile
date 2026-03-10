# Start from the official OpenLiteSpeed image pre-loaded with PHP 8.2
FROM litespeedtech/openlitespeed:1.7.19-lsphp82

# Install Magento required extensions for LSPHP + Node.js/Grunt
RUN apt-get update && apt-get install -y \
    wget curl git unzip nano cron mariadb-client \
    lsphp82-mysql lsphp82-opcache lsphp82-intl lsphp82-gd \
    lsphp82-bcmath lsphp82-soap lsphp82-zip lsphp82-sodium lsphp82-redis \
    lsphp82-xdebug \
    nodejs npm \
    && npm install -g grunt-cli

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Fix Permissions: OpenLiteSpeed uses 'nobody' instead of 'www-data'
# We map 'nobody' to your WSL user ID (1000) to prevent locked files in Windows
RUN usermod -u 1000 nobody && groupmod -g 1000 nogroup

# Configure OpenLiteSpeed to point to the Magento pub directory and read .htaccess
RUN sed -i 's|docRoot                   $VH_ROOT/html/|docRoot                   /var/www/html/pub/|g' /usr/local/lsws/conf/vhosts/Example/vhconf.xml \
    && sed -i 's|allowSetUID               0|allowSetUID               1\n  allowOverride           1\n  enableCache             1|g' /usr/local/lsws/conf/vhosts/Example/vhconf.xml

# Symlink LSPHP to standard PHP command for CLI usage
RUN ln -sf /usr/local/lsws/lsphp82/bin/php /usr/bin/php

# Set working directory
WORKDIR /var/www/html

# Expose standard HTTP/HTTPS and LiteSpeed WebAdmin ports
EXPOSE 80 443 7080
