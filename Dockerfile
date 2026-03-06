FROM almalinux:8.8

# FIX 1: Import updated AlmaLinux GPG Keys
RUN rpm --import https://repo.almalinux.org/almalinux/RPM-GPG-KEY-AlmaLinux

# Install EPEL, Remi repositories, and wget/tar
RUN dnf install -y epel-release https://rpms.remirepo.net/enterprise/remi-release-8.rpm \
    && dnf install -y wget tar \
    && dnf module reset php -y \
    && dnf module enable php:remi-8.2 -y

# Install Apache, Git, Composer dependencies, Magento PHP extensions, and Xdebug
RUN dnf install -y \
    httpd git unzip curl \
    php php-cli php-fpm php-mysqlnd php-zip php-gd php-mbstring \
    php-curl php-xml php-pear php-bcmath php-json php-intl \
    php-soap php-opcache php-sodium \
    php-pecl-xdebug3

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Configure Mailpit for local email testing
RUN wget https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64 -O /usr/local/bin/mhsendmail \
    && chmod +x /usr/local/bin/mhsendmail \
    && echo 'sendmail_path = "/usr/local/bin/mhsendmail --smtp-addr=mailpit:1025"' > /etc/php.d/99-mailpit.ini

# Configure Xdebug 3 for Remote Debugging
RUN echo -e "xdebug.mode=debug\n\
xdebug.start_with_request=yes\n\
xdebug.client_host=host.docker.internal\n\
xdebug.client_port=9003\n\
xdebug.idekey=VSCODE\n\
xdebug.log=/var/log/xdebug.log" > /etc/php.d/15-xdebug.ini

# Increase PHP memory limit to 10GB for heavy Magento compilation
RUN echo "memory_limit = 10G" > /etc/php.d/99-magento-custom.ini

# Configure Apache securely (AllowOverrides and DocumentRoot -> /pub)
RUN sed -i 's/AllowOverride None/AllowOverride All/g' /etc/httpd/conf/httpd.conf \
    && echo -e "\n<VirtualHost *:80>\n    DocumentRoot /var/www/html/pub\n    <Directory /var/www/html>\n        AllowOverride All\n        Require all granted\n    </Directory>\n</VirtualHost>" >> /etc/httpd/conf/httpd.conf

WORKDIR /var/www/html
EXPOSE 80

# FIX 2: Start PHP-FPM in the background, then start Apache in the foreground
CMD mkdir -p /run/php-fpm && php-fpm -D && httpd -D FOREGROUND