#!/bin/bash

# ==========================================
# 🛑 INITIALIZATION & DOWNLOADS
# ==========================================
# CHANGE THIS: The raw URL of your public repository branch
REPO_BASE_URL="https://raw.githubusercontent.com/Chris-Weeks/docker-magento-setup/main"

echo "🚀 Welcome to the Magento 2 Local Environment Setup"
echo "⬇️  Downloading Docker configurations from public repository..."

# Download the required Docker files silently
curl -sS -o docker-compose.yml "$REPO_BASE_URL/docker-compose.yml"
curl -sS -o Dockerfile "$REPO_BASE_URL/Dockerfile"
curl -sS -o toggle-xdebug.sh "$REPO_BASE_URL/toggle-xdebug.sh"
chmod +x toggle-xdebug.sh

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
    
    # Require Magento Keys
    while [ -z "$MAGENTO_PUB_KEY" ]; do read -p "Magento Public Key [Required]: " MAGENTO_PUB_KEY; done
    while [ -z "$MAGENTO_PRIV_KEY" ]; do read -p "Magento Private Key [Required]: " MAGENTO_PRIV_KEY; done

    # Optional variables with defaults
    read -p "Base URL [http://localhost:8000/]: " BASE_URL
    BASE_URL=${BASE_URL:-http://localhost:8000/}

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

    # Generate the .env file
    cat <<EOF > .env
MAGENTO_PUB_KEY=$MAGENTO_PUB_KEY
MAGENTO_PRIV_KEY=$MAGENTO_PRIV_KEY
EOF

elif [ "$INSTALL_TYPE" == "2" ]; then
    echo ""
    echo "--- ☁️ EXISTING REPOSITORY CONFIGURATION ---"
    
    echo "💡 Tip: Use an SSH URL (git@...) or include your token (https://<token>@...) to bypass prompts."
    while [ -z "$GIT_REPO_URL" ]; do read -p "Git Repository URL: " GIT_REPO_URL; done

    while [ -z "$MAGENTO_PUB_KEY" ]; do read -p "Magento Public Key [Required for Composer]: " MAGENTO_PUB_KEY; done
    while [ -z "$MAGENTO_PRIV_KEY" ]; do read -p "Magento Private Key [Required for Composer]: " MAGENTO_PRIV_KEY; done

    echo ""
    echo "--- 🧩 THIRD-PARTY MODULES (Optional) ---"
    echo "If your repo requires third-party keys (like Amasty, Mageplaza), enter them below."
    echo "Press Enter with a blank URL to finish or skip."

    VENDOR_COUNT=0
    while true; do
        echo ""
        read -p "Vendor Composer URL (e.g., composer.amasty.com) [Blank to exit]: " V_URL
        
        if [ -z "$V_URL" ]; then
            break
        fi
        
        read -p "Vendor Username / Public Key: " V_PUB
        read -p "Vendor Password / Private Key: " V_PRIV

        VENDOR_COUNT=$((VENDOR_COUNT+1))
        
        # Store variables dynamically
        export VENDOR_URL_$VENDOR_COUNT="$V_URL"
        export VENDOR_PUB_KEY_$VENDOR_COUNT="$V_PUB"
        export VENDOR_PRIV_KEY_$VENDOR_COUNT="$V_PRIV"
    done

    # Generate the base .env file
    cat <<EOF > .env
GIT_REPO_URL=$GIT_REPO_URL
MAGENTO_PUB_KEY=$MAGENTO_PUB_KEY
MAGENTO_PRIV_KEY=$MAGENTO_PRIV_KEY
VENDOR_COUNT=$VENDOR_COUNT
EOF

    # Append the dynamic third-party keys to the .env file
    for (( i=1; i<=$VENDOR_COUNT; i++ )); do
        U_VAR="VENDOR_URL_$i"
        PUB_VAR="VENDOR_PUB_KEY_$i"
        PRIV_VAR="VENDOR_PRIV_KEY_$i"
        
        echo "$U_VAR=${!U_VAR}" >> .env
        echo "$PUB_VAR=${!PUB_VAR}" >> .env
        echo "$PRIV_VAR=${!PRIV_VAR}" >> .env
    done

    # Default values for the Existing Repo installation step
    BASE_URL="http://localhost:8000/"
    ADMIN_FIRST="Dev"
    ADMIN_LAST="Admin"
    ADMIN_EMAIL="admin@example.com"
    ADMIN_USER="admin"
    ADMIN_PASS="AdminPassword123!"

else
    echo "❌ Invalid selection. Exiting."
    exit 1
fi

# ==========================================
# 🐳 DOCKER BUILD & INITIALIZATION
# ==========================================
echo ""
echo "🐳 Building Docker environment..."
docker-compose up -d --build

echo "⏳ Waiting 30s for MariaDB to initialize..."
sleep 30

# ==========================================
# 📦 INSTALLATION EXECUTION
# ==========================================
if [ "$INSTALL_TYPE" == "1" ]; then
    echo "🔑 Authenticating Composer globally..."
    docker-compose exec -T web composer config -g http-basic.repo.magento.com "$MAGENTO_PUB_KEY" "$MAGENTO_PRIV_KEY"

    if [ ! -f "magento-src/bin/magento" ]; then
        echo "📥 Downloading fresh Magento 2.4.7-p8..."
        docker-compose exec -T web composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition=2.4.7-p8 .
    else
        echo "✅ Magento codebase already exists. Skipping download."
    fi

elif [ "$INSTALL_TYPE" == "2" ]; then
    if [ ! -d "magento-src/.git" ]; then
        echo "📦 Cloning Repository..."
        git clone "$GIT_REPO_URL" magento-src
    else
        echo "✅ Repository already exists in magento-src/. Skipping clone."
    fi

    echo "🔑 Authenticating standard Magento Repo globally..."
    docker-compose exec -T web composer config -g http-basic.repo.magento.com "$MAGENTO_PUB_KEY" "$MAGENTO_PRIV_KEY"

    # Loop through and authenticate all third-party vendors
    if [ "$VENDOR_COUNT" -gt 0 ]; then
        for (( i=1; i<=$VENDOR_COUNT; i++ )); do
            U_VAR="VENDOR_URL_$i"
            PUB_VAR="VENDOR_PUB_KEY_$i"
            PRIV_VAR="VENDOR_PRIV_KEY_$i"
            
            V_URL="${!U_VAR}"
            V_PUB="${!PUB_VAR}"
            V_PRIV="${!PRIV_VAR}"
            
            echo "🧩 Authenticating Third-Party Vendor ($V_URL)..."
            docker-compose exec -T web composer config -g http-basic."$V_URL" "$V_PUB" "$V_PRIV"
        done
    fi

    echo "📥 Installing Composer dependencies..."
    docker-compose exec -T web composer install -d /var/www/html
fi

# ==========================================
# ⚙️ MAGENTO CONFIGURATION
# ==========================================
echo "⚙️ Running Magento setup:install..."
docker-compose exec -T web bin/magento setup:install \
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
    --language="en_US" \
    --currency="USD" \
    --timezone="UTC" \
    --use-rewrites="1" \
    --search-engine="elasticsearch7" \
    --elasticsearch-host="elasticsearch" \
    --elasticsearch-port="9200"

echo "⚡ Linking Redis and RabbitMQ..."
docker-compose exec -T web bin/magento setup:config:set --cache-backend=redis --cache-backend-redis-server=redis --cache-backend-redis-db=0 -n
docker-compose exec -T web bin/magento setup:config:set --page-cache=redis --page-cache-redis-server=redis --page-cache-redis-db=1 -n
docker-compose exec -T web bin/magento setup:config:set --session-save=redis --session-save-redis-host=redis --session-save-redis-log-level=4 --session-save-redis-db=2 -n
docker-compose exec -T web bin/magento setup:config:set --amqp-host=rabbitmq --amqp-port=5672 --amqp-user=guest --amqp-password=guest -n

echo "🧹 Clearing Cache..."
docker-compose exec -T web bin/magento cache:flush
docker-compose exec -T web chmod -R 777 var/ pub/static/ generated/

# ==========================================
# 🛠️ DEVELOPER ALIAS SETUP
# ==========================================
echo "🛠️ Configuring WSL Developer Aliases..."
ALIAS_MARKER="# Magento 2 Docker Aliases"

# Check if aliases already exist to prevent duplicating them
if ! grep -q "$ALIAS_MARKER" ~/.bashrc; then
    cat << 'EOF' >> ~/.bashrc

# Magento 2 Docker Aliases
alias m="docker-compose exec web bin/magento"
alias mc="docker-compose exec web composer"
alias mcli="docker-compose exec web bash"
alias mclean="docker-compose exec web bash -c 'rm -rf var/cache/* var/page_cache/* var/view_preprocessed/* generated/code/* generated/metadata/* pub/static/frontend/* pub/static/adminhtml/* && bin/magento cache:flush && chmod -R 777 var/ pub/static/ generated/'"
EOF
    echo "✅ Aliases added successfully! (Run 'source ~/.bashrc' or restart your terminal to use them)."
else
    echo "✅ Aliases already configured in ~/.bashrc."
fi

# ==========================================
# 🎉 FINISH
# ==========================================
echo "🎉 BOOM! Setup Complete!"
echo "🛒 Storefront: $BASE_URL"
echo "🗄️  phpMyAdmin: http://localhost:8081"
echo "🐇 RabbitMQ: http://localhost:15672"
echo "📬 Mailpit: http://localhost:8025"