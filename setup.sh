#!/bin/bash

# ==========================================
# ?? LOAD CONFIGURATION
# ==========================================
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "? Error: .env file not found. Copy .env.example to .env and fill it out."
    exit 1
fi

AZURE_CLONE_URL="https://${AZURE_PAT}@dev.azure.com/${AZURE_ORG}/${AZURE_PROJECT}/_git/${AZURE_REPO_NAME}"

# ==========================================
# ?? AUTOMATION STEPS
# ==========================================
echo "?? Starting Automated Custom Magento 2 Environment Setup..."

if [ ! -d "magento-src" ]; then
    echo "?? Cloning Azure Repository..."
    git clone $AZURE_CLONE_URL magento-src
else
    echo "? Directory 'magento-src' already exists. Skipping clone."
fi

echo "?? Setting up Composer Authentication..."
cat <<EOF > magento-src/auth.json
{
    "http-basic": {
        "repo.magento.com": {
            "username": "${MAGENTO_PUB_KEY}",
            "password": "${MAGENTO_PRIV_KEY}"
        }
    }
}
EOF

echo "?? Building and starting Docker containers..."
docker-compose up -d --build

echo "? Waiting for databases to initialize (sleeping for 30s)..."
sleep 30

echo "?? Installing Composer dependencies..."
docker-compose exec -T web composer install -d /var/www/html

echo "?? Running Magento setup:install..."
docker-compose exec -T web bin/magento setup:install \
    --base-url="http://magento.test:8000/" \
    --db-host="db" \
    --db-name="magento" \
    --db-user="magento" \
    --db-password="magentopassword" \
    --admin-firstname="Dev" \
    --admin-lastname="Admin" \
    --admin-email="admin@example.com" \
    --admin-user="admin" \
    --admin-password="AdminPassword123!" \
    --language="en_US" \
    --currency="USD" \
    --timezone="UTC" \
    --use-rewrites="1" \
    --search-engine="elasticsearch7" \
    --elasticsearch-host="elasticsearch" \
    --elasticsearch-port="9200"

echo "? Configuring Redis for Cache, Full Page Cache, and Sessions..."
docker-compose exec -T web bin/magento setup:config:set --cache-backend=redis --cache-backend-redis-server=redis --cache-backend-redis-db=0 -n
docker-compose exec -T web bin/magento setup:config:set --page-cache=redis --page-cache-redis-server=redis --page-cache-redis-db=1 -n
docker-compose exec -T web bin/magento setup:config:set --session-save=redis --session-save-redis-host=redis --session-save-redis-log-level=4 --session-save-redis-db=2 -n

echo "?? Configuring RabbitMQ..."
docker-compose exec -T web bin/magento setup:config:set --amqp-host=rabbitmq --amqp-port=5672 --amqp-user=guest --amqp-password=guest -n

echo "?? Clearing Cache and Setting Permissions..."
docker-compose exec -T web bin/magento cache:flush
docker-compose exec -T web chmod -R 777 var/ pub/static/ generated/

echo "?? BOOM! Setup Complete!"
echo "?? Storefront: http://magento.test:8000"
echo "???  phpMyAdmin: http://localhost:8081"
echo "?? RabbitMQ: http://localhost:15672"
echo "?? Mailpit: http://localhost:8025"