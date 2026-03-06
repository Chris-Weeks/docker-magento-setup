#!/bin/bash

CONTAINER="web"
XDEBUG_INI="/usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini"
XDEBUG_DISABLED="/usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini.disabled"

echo "🔍 Checking current Xdebug status..."

# Check if the active xdebug.ini file exists inside the container
IS_ENABLED=$(docker-compose exec -T $CONTAINER bash -c "if [ -f $XDEBUG_INI ]; then echo 'yes'; else echo 'no'; fi")

if [ "$IS_ENABLED" == "yes" ]; then
    echo "🛑 Disabling Xdebug..."
    # Rename the ini file so PHP ignores it
    docker-compose exec -T $CONTAINER mv $XDEBUG_INI $XDEBUG_DISABLED
    
    # Gracefully reload Apache (Debian uses apache2ctl instead of httpd)
    docker-compose exec -T $CONTAINER apache2ctl graceful
    
    echo "✅ Xdebug is now OFF. Magento should be fast again!"
else
    echo "🟢 Enabling Xdebug..."
    # Rename the file back to .ini so PHP loads it
    docker-compose exec -T $CONTAINER mv $XDEBUG_DISABLED $XDEBUG_INI
    
    # Gracefully reload Apache
    docker-compose exec -T $CONTAINER apache2ctl graceful
    
    echo "✅ Xdebug is now ON. Ready to catch breakpoints!"
fi