#!/bin/bash
set -e # Safety switch: Stop the script immediately if any command fails

# ==========================================
# 🛑 INITIALIZATION & DOWNLOADS
# ==========================================
REPO_BASE_URL="https://raw.githubusercontent.com/Chris-Weeks/docker-magento-setup/main"

echo "🚀 Welcome to the Magento 2 Local Environment Setup"
echo "⬇️  Downloading Docker configurations from public repository..."

curl -sS -o docker-compose.yml "$REPO_BASE_URL/docker-compose.yml"
curl -sS -o Dockerfile "$REPO_BASE_URL/Dockerfile"
curl -sS -o toggle-xdebug.sh "$REPO_BASE_URL/toggle-xdebug.sh"
chmod +x toggle-xdebug.sh

# Grab the local host's User ID and Group ID
LOCAL_UID=$(id -u)
LOCAL_GID=$(id -g)

# Start building the .env file
echo "UID=$LOCAL_UID" > .env
echo "GID=$LOCAL_GID" >> .env

# ==========================================
# 🗣️ INTERACTIVE PROMPTS
# ==========================================
echo ""
echo "Which type of installation do you need?"
echo "1) Clean Slate (Fresh Magento 2.4.7-p8 Install)"
echo "2) Existing Repository (Pull from Git)"
read -p "Enter 1 or 2: " INSTALL_TYPE

if [ "$INSTALL_TYPE" == "1" ]; then
    echo ""
    echo "--- 🧼 CLEAN SLATE CONFIGURATION ---"
    while [ -z "$MAGENTO_PUB_KEY" ]; do read -p "Magento Public Key [Required]: " MAGENTO_PUB_KEY; done
    while [ -z "$MAGENTO_PRIV_KEY" ]; do read -p "Magento Private Key [Required]: " MAGENTO_PRIV_KEY; done

elif [ "$INSTALL_TYPE" == "2" ]; then
    echo ""
    echo "--- ☁️ EXISTING REPOSITORY CONFIGURATION ---"
    echo "💡 Tip: Use an SSH URL (git@...) or include your token (https://<token>@...) to bypass prompts."
    while [ -z "$GIT_REPO_URL" ]; do read -p "Git Repository URL: " GIT_REPO_URL; done

    while [ -z "$MAGENTO_PUB_KEY" ]; do read -p "Magento Public Key [Required for Composer]: " MAGENTO_PUB_KEY; done
    while [ -z "$MAGENTO_PRIV_KEY" ]; do read -p "Magento Private Key [Required for Composer]: " MAGENTO_PRIV_KEY; done

    echo ""
    echo "--- 🧩 THIRD-PARTY MODULES (Optional) ---"
    VENDOR_COUNT=0
    while true; do
        read -p "Vendor Composer URL (e.g., composer.amasty.com) [Blank to exit]: " V_URL
        if [ -z "$V_URL" ]; then break; fi
        read -p "Vendor Username / Public Key: " V_PUB
        read -p "Vendor Password / Private Key: " V_PRIV

        VENDOR_COUNT=$((VENDOR_COUNT+1))
        echo "VENDOR_URL_$VENDOR_COUNT=$V_URL" >> .env
        echo "VENDOR_PUB_KEY_$VENDOR_COUNT=$V_PUB" >> .env
        echo "VENDOR_PRIV_KEY_$VENDOR_COUNT=$V_PRIV" >> .env
    done
    echo "GIT_REPO_URL=$GIT_REPO_URL" >> .env
    echo "VENDOR_COUNT=$VENDOR_COUNT" >> .env
else
    echo "❌ Invalid selection. Exiting."
    exit 1
fi

echo "MAGENTO_PUB_KEY=$MAGENTO_PUB_KEY" >> .env
echo "MAGENTO_PRIV_KEY=$MAGENTO_PRIV_KEY" >> .env

# ==========================================
# 🔍 PRE-FLIGHT PORT DETECTION
# ==========================================
echo ""
echo "--- 🔍 PORT AVAILABILITY CHECK ---"

check_port() {
    local port=$1
    local service=$2
    local env_var=$3

    # Check if port is in use using bash network sockets
    while (echo >/dev/tcp/127.0.0.1/$port) >/dev/null 2>&1; do
        echo "⚠️  Port $port is already in use (needed for $service)."
        read -p "Enter an alternative port (e.g., $((port + 1))): " new_port
        port=$new_port
    done
    
    echo "$env_var=$port" >> .env
    echo "✅ $service will use port $port"
}

check_port 80 "Magento Web" "WEB_PORT"
check_port 3306 "MariaDB" "DB_PORT"
check_port 9200 "Elasticsearch" "ES_PORT"
check_port 6379 "Redis" "REDIS_PORT"
check_port 5672 "RabbitMQ AMQP" "RMQ_PORT"
check_port 15672 "RabbitMQ UI" "RMQ_MGMT_PORT"
check_port 8081 "phpMyAdmin" "PMA_PORT"
check_port 8025 "Mailpit UI" "MAILPIT_UI_PORT"
check_port 1025 "Mailpit SMTP" "MAILPIT_SMTP_PORT"

# Grab the web port from the .env file to help with the Base URL prompt
FINAL_WEB_PORT=$(grep WEB_PORT .env | cut -d '=' -f 2)
SUGGESTED_URL="http://magento.test/"
if [ "$FINAL_WEB_PORT" != "80" ]; then
    SUGGESTED_URL="http://magento.test:$FINAL_WEB_PORT/"
fi

# ==========================================
# 🌍 SHARED SITE SETTINGS
# ==========================================
echo ""
echo "--- 🌍 GENERAL SITE SETTINGS ---"
read -p "Base URL [$SUGGESTED_URL]: " BASE_URL
BASE_URL=${BASE_URL:-$SUGGESTED_URL}

read -p "Admin First Name [Dev]: " ADMIN_FIRST
ADMIN_FIRST=${ADMIN_FIRST:-Dev}
read -p "Admin Last Name [Admin]: " ADMIN_LAST
ADMIN_LAST=${ADMIN_LAST:-Admin}
read -p "Admin Email [admin@example.com]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@example.com}
read -p "Admin Username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}
read -p "Admin Password [AdminPassword123!]: " ADMIN_PASS
ADMIN_PASS=${ADMIN_PASS:-AdminPassword123!}
read -p "Default Language [en_US]: " MAGENTO_LANG
MAGENTO_LANG=${MAGENTO_LANG:-en_US}
read -p "Default Currency [USD]: " MAGENTO_CURRENCY
MAGENTO_CURRENCY=${MAGENTO_CURRENCY:-USD}

# ==========================================
# 🐳 DOCKER BUILD
# ==========================================
mkdir -p magento-src

echo ""
echo "🐳 Building Docker environment..."
docker-compose up -d --build

echo "⏳ Waiting 30s for MariaDB to initialize..."
sleep 30

# ==========================================
# 📥 MAGENTO INSTALLATION
# ==========================================
echo "🔑 Authenticating standard Magento Repo globally..."
docker-compose exec -T --user www-data web composer config -g http-basic.repo.magento.com "$MAGENTO_PUB_KEY" "$MAGENTO_PRIV_KEY"

if [ ! -f "magento-src/bin/magento" ]; then
    echo "📥 Downloading fresh base Magento 2.4.7-p8..."
    docker-compose exec -T --user www-data web composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition=2.4.7-p8 .
fi

if [ ! -f "magento-src/app/etc/env.php" ]; then
    echo "⚙️ Running base Magento setup:install..."
    docker-compose exec -T --user www-data web bin/magento setup:install \
        --base-url="$BASE_URL" \
        --db-host="db" \
        --db-name="magento" \
        --db-user="magento" \
        --db-password="magentopassword" \
        --admin-firstname="$ADMIN_FIRST" \
        --admin-lastname="$ADMIN_LAST" \
        --admin-email="$ADMIN_EMAIL" \
        --admin-user="$ADMIN_USER" \
        --admin-password="$ADMIN_PASS" \
        --language="$MAGENTO_LANG" \
        --currency="$MAGENTO_CURRENCY" \
        --timezone="UTC" \
        --use-rewrites="1" \
        --search-engine="elasticsearch7" \
        --elasticsearch-host="elasticsearch" \
        --elasticsearch-port="9200"
fi

# ==========================================
# 🔄 MERGE & UPGRADE EXISTING REPO
# ==========================================
if [ "$INSTALL_TYPE" == "2" ]; then
    echo "📦 Pulling custom repository into a temporary folder..."
    git clone "$GIT_REPO_URL" ../magento-temp-repo

    echo "🔄 Merging custom repository over base install..."
    cp -a ../magento-temp-repo/. ./magento-src/
    rm -rf ../magento-temp-repo

    echo "🔧 Fixing potential Windows line-ending conflicts..."
    sed -i 's/\r$//' ./magento-src/bin/magento
    chmod +x ./magento-src/bin/magento

    if [ "$VENDOR_COUNT" -gt 0 ]; then
        for (( i=1; i<=$VENDOR_COUNT; i++ )); do
            U_VAR="VENDOR_URL_$i"
            PUB_VAR="VENDOR_PUB_KEY_$i"
            PRIV_VAR="VENDOR_PRIV_KEY_$i"
            
            V_URL="${!U_VAR}"
            V_PUB="${!PUB_VAR}"
            V_PRIV="${!PRIV_VAR}"
            
            echo "🧩 Authenticating Third-Party Vendor ($V_URL)..."
            docker-compose exec -T --user www-data web composer config -g http-basic."$V_URL" "$V_PUB" "$V_PRIV"
        done
    fi

    echo "📥 Installing custom Composer dependencies..."
    docker-compose exec -T --user www-data web composer install -d /var/www/html

    echo "🚀 Running setup:upgrade to register custom modules..."
    docker-compose exec -T --user www-data web bin/magento setup:upgrade
fi

# ==========================================
# ⚙️ FINAL CONFIGURATION
# ==========================================
echo "⚡ Linking Redis and RabbitMQ..."
docker-compose exec -T --user www-data web bin/magento setup:config:set --cache-backend=redis --cache-backend-redis-server=redis --cache-backend-redis-db=0 -n
docker-compose exec -T --user www-data web bin/magento setup:config:set --page-cache=redis --page-cache-redis-server=redis --page-cache-redis-db=1 -n
docker-compose exec -T --user www-data web bin/magento setup:config:set --session-save=redis --session-save-redis-host=redis --session-save-redis-log-level=4 --session-save-redis-db=2 -n
docker-compose exec -T --user www-data web bin/magento setup:config:set --amqp-host=rabbitmq --amqp-port=5672 --amqp-user=guest --amqp-password=guest -n

echo "🧹 Clearing Cache..."
docker-compose exec -T --user www-data web bin/magento cache:flush
docker-compose exec -T --user www-data web bash -c "chmod -R 777 var/ pub/static/ pub/media/ generated/ || true"

# ==========================================
# 🛠️ DEVELOPER ALIAS SETUP
# ==========================================
echo "🛠️ Configuring WSL Developer Aliases..."
ALIAS_MARKER="# Magento 2 Docker Aliases"

if ! grep -q "$ALIAS_MARKER" ~/.bashrc; then
    cat << 'EOF' >> ~/.bashrc

# Magento 2 Docker Aliases
alias m="docker-compose exec --user www-data web bin/magento"
alias mc="docker-compose exec --user www-data web composer"
alias mcli="docker-compose exec --user www-data web bash"
alias mclean="docker-compose exec --user www-data web bash -c 'rm -rf var/cache/* var/page_cache/* var/view_preprocessed/* generated/code/* generated/metadata/* pub/static/frontend/* pub/static/adminhtml/* && bin/magento cache:flush && chmod -R 777 var/ pub/static/ pub/media/ generated/'"
EOF
    echo "✅ Aliases added successfully! (Run 'source ~/.bashrc' or restart your terminal to use them)."
else
    echo "✅ Aliases already configured in ~/.bashrc."
fi

# ==========================================
# 🎉 FINISH
# ==========================================
FINAL_PMA_PORT=$(grep PMA_PORT .env | cut -d '=' -f 2)
FINAL_RMQ_MGMT=$(grep RMQ_MGMT_PORT .env | cut -d '=' -f 2)
FINAL_MAILPIT=$(grep MAILPIT_UI_PORT .env | cut -d '=' -f 2)

echo "🎉 BOOM! Setup Complete!"
echo "🛒 Storefront: $BASE_URL"
echo "🗄️  phpMyAdmin: http://localhost:$FINAL_PMA_PORT"
echo "🐇 RabbitMQ: http://localhost:$FINAL_RMQ_MGMT"
echo "📬 Mailpit: http://localhost:$FINAL_MAILPIT"
