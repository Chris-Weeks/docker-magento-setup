FROM php:8.2-apache

# 1. Map the container's www-data user to the host's UID/GID to prevent permission errors
ARG UID=1000
ARG GID=1000
RUN usermod -u ${UID} www-data && groupmod -g ${GID} www-data

# 2. Ensure www-data owns its home directory so Composer can write global auth configs
RUN mkdir -p /var/www/.composer && chown -R www-data:www-data /var/www

# 3. Install required system packages (added curl & gnupg for Node.js)
RUN apt-get update && apt-get install -y \
    libfreetype6-dev libjpeg62-turbo-dev libpng-dev libicu-dev \
    libzip-dev libxslt1-dev git unzip wget nano libsodium-dev libxml2-dev curl gnupg

# 4. Install Node.js 18.x and Grunt CLI globally
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g grunt-cli

# 5. Configure and install PHP extensions required by Magento 2.4.7
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd bcmath intl pdo_mysql soap xsl zip sockets sodium opcache

# 6. Enable Apache Mod Rewrite for Magento Routing
RUN a2enmod rewrite

# 7. Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# 8. Install Xdebug (Disabled by default so it doesn't slow down the site. Use toggle script to enable)
RUN pecl install xdebug-3.2.1 \
    && echo "zend_extension=xdebug.so\n\
xdebug.mode=debug\n\
xdebug.start_with_request=yes\n\
xdebug.client_host=host.docker.internal\n\
xdebug.client_port=9003\n\
xdebug.idekey=VSCODE" > /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini.disabled

# 9. Install Mailpit routing
RUN wget https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64 -O /usr/local/bin/mhsendmail \
    && chmod +x /usr/local/bin/mhsendmail \
    && echo 'sendmail_path = "/usr/local/bin/mhsendmail --smtp-addr=mailpit:1025"' > /usr/local/etc/php/conf.d/mailpit.ini

# 10. Increase Memory Limit to 10GB
RUN echo "memory_limit = 10G" > /usr/local/etc/php/conf.d/magento-memory.ini

# 11. Update Apache DocumentRoot to point to Magento's /pub folder securely
ENV APACHE_DOCUMENT_ROOT /var/www/html/pub
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

WORKDIR /var/www/html
