#!/bin/bash

# Define the container name (matches the service name in docker-compose)
CONTAINER="web"

echo "🔍 Checking current Xdebug status..."

# Check if the active xdebug.ini file exists inside the container
IS_ENABLED=$(docker-compose exec -T $CONTAINER bash -c "if [ -f /etc/php.d/15-xdebug.ini ]; then echo 'yes'; else echo 'no'; fi")

if [ "$IS_ENABLED" == "yes" ]; then
    echo "🛑 Disabling Xdebug..."
    # Rename the ini file so PHP ignores it
    docker-compose exec -T $CONTAINER mv /etc/php.d/15-xdebug.ini /etc/php.d/15-xdebug.ini.disabled
    
    # Gracefully reload Apache to apply the changes without killing the container
    docker-compose exec -T $CONTAINER httpd -k graceful
    
    echo "✅ Xdebug is now OFF. Magento should be fast again!"
else
    echo "🟢 Enabling Xdebug..."
    # Rename the file back to .ini so PHP loads it
    docker-compose exec -T $CONTAINER mv /etc/php.d/15-xdebug.ini.disabled /etc/php.d/15-xdebug.ini
    
    # Gracefully reload Apache
    docker-compose exec -T $CONTAINER httpd -k graceful
    
    echo "✅ Xdebug is now ON. Ready to catch breakpoints!"
fi