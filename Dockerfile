FROM php:8.2-apache

# 1. Map the container's www-data user to the host's UID/GID to prevent permission errors
ARG UID=1000
ARG GID=1000
RUN usermod -u ${UID} www-data && groupmod -g ${GID} www-data

# 2. Install required system packages (including libsodium-dev and libxml2-dev)
RUN apt-get update && apt-get install -y \
    libfreetype6-dev libjpeg62-turbo-dev libpng-dev libicu-dev \
    libzip-dev libxslt1-dev git unzip wget nano libsodium-dev libxml2-dev

# 3. Configure and install PHP extensions required by Magento 2.4.7
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd bcmath intl pdo_mysql soap xsl zip sockets sodium opcache

# 4. Enable Apache Mod Rewrite for Magento Routing
RUN a2enmod rewrite

# 5. Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# 6. Install Xdebug (Disabled by default so it doesn't slow down the site. Use toggle script to enable)
RUN pecl install xdebug-3.2.1 \
    && echo "zend_extension=xdebug.so\n\
xdebug.mode=debug\n\
xdebug.start_with_request=yes\n\
xdebug.client_host=host.docker.internal\n\
xdebug.client_port=9003\n\
xdebug.idekey=VSCODE" > /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini.disabled

# 7. Install Mailpit routing
RUN wget https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64 -O /usr/local/bin/mhsendmail \
    && chmod +x /usr/local/bin/mhsendmail \
    && echo 'sendmail_path = "/usr/local/bin/mhsendmail --smtp-addr=mailpit:1025"' > /usr/local/etc/php/conf.d/mailpit.ini

# 8. Increase Memory Limit to 10GB
RUN echo "memory_limit = 10G" > /usr/local/etc/php/conf.d/magento-memory.ini

# 9. Update Apache DocumentRoot to point to Magento's /pub folder securely
ENV APACHE_DOCUMENT_ROOT /var/www/html/pub
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

WORKDIR /var/www/htmlFROM php:8.2-apache

# Install required system packages
RUN apt-get update && apt-get install -y \
    libfreetype6-dev libjpeg62-turbo-dev libpng-dev libicu-dev \
    libzip-dev libxslt1-dev git unzip wget nano libsodium-dev libxml2-dev

# Configure and install PHP extensions required by Magento 2.4.7
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd bcmath intl pdo_mysql soap xsl zip sockets sodium opcache

# Enable Apache Mod Rewrite for Magento Routing
RUN a2enmod rewrite

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Install Xdebug (disabled by default, can be toggled later)
RUN pecl install xdebug \
    && docker-php-ext-enable xdebug \
    && echo "xdebug.mode=debug\n\
xdebug.start_with_request=yes\n\
xdebug.client_host=host.docker.internal\n\
xdebug.client_port=9003\n\
xdebug.idekey=VSCODE" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

# Install Mailpit routing
RUN wget https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64 -O /usr/local/bin/mhsendmail \
    && chmod +x /usr/local/bin/mhsendmail \
    && echo 'sendmail_path = "/usr/local/bin/mhsendmail --smtp-addr=mailpit:1025"' > /usr/local/etc/php/conf.d/mailpit.ini

# Increase Memory Limit to 10GB
RUN echo "memory_limit = 10G" > /usr/local/etc/php/conf.d/magento-memory.ini

# Update Apache DocumentRoot to point to Magento's /pub folder securely
ENV APACHE_DOCUMENT_ROOT /var/www/html/pub
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

WORKDIR /var/www/html
