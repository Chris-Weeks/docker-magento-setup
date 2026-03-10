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

LOCAL_UID=$(id -u)
LOCAL_GID=$(id -g)
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
        
        # 🧹 AUTOMATIC CLEANUP: Strip http://, https://, and trailing slashes so Composer doesn't break
        V_URL=$(echo "$V_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')

        read -p "Vendor Username / Public Key: " V_PUB
        read -p "Vendor Password / Private Key: " V_PRIV

        VENDOR_COUNT=$((VENDOR_COUNT+1))
        
        # 1. Keep in script's active memory for the Composer command
        export VENDOR_URL_${VENDOR_COUNT}="$V_URL"
        export VENDOR_PUB_KEY_${VENDOR_COUNT}="$V_PUB"
        export VENDOR_PRIV_KEY_${VENDOR_COUNT}="$V_PRIV"
        
        # 2. Save to .env file for Docker
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
# 🔍 PRE-FLIGHT PORT DETECTION (Self-Aware + WSL + Windows)
# ==========================================
echo ""
echo "--- 🔍 PORT AVAILABILITY CHECK ---"

check_port() {
    local port=$1
    local service=$2
    local env_var=$3

    while true; do
        PORT_IN_USE=false
        
        # 1. Check if the port was ALREADY assigned in this exact script run
        if grep -q "=$port$" .env 2>/dev/null; then
            PORT_IN_USE=true
        fi
        
        # 2. Check WSL/Linux network (using nc, ss, or bash tcp)
        if [ "$PORT_IN_USE" = false ]; then
            if (command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$port" >/dev/null 2>&1) || \
               (command -v ss >/dev/null 2>&1 && ss -tuln | grep -q ":$port ") || \
               ( (echo >/dev/tcp/127.0.0.1/$port) >/dev/null 2>&1 ); then
                PORT_IN_USE=true
            fi
        fi

        # 3. Check Windows Host network (Safely via interop)
        if [ "$PORT_IN_USE" = false ] && command -v netstat.exe >/dev/null 2>&1; then
            # The 2>/dev/null catches the "Exec format error" if WSL interop is broken
            if netstat.exe -an 2>/dev/null | grep -q -E ":$port\s+.*LISTENING"; then
                PORT_IN_USE=true
            fi
        fi

        if [ "$PORT_IN_USE" = true ]; then
            echo "⚠️  Port $port is already in use or claimed by another container (needed for $service)."
            read -p "Enter an alternative port (e.g., $((port + 1))): " new_port
            
            if [[ "$new_port" =~ ^[0-9]+$ ]]; then
                port=$new_port
            else
                echo "❌ Invalid port number. Please enter a valid number."
            fi
        else
            break
        fi
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

# 🌐 AUTOMATIC WINDOWS HOSTS FILE INJECTION
DOMAIN=$(echo "$BASE_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||')
if [[ "$DOMAIN" != "localhost" && "$DOMAIN" != "127.0.0.1" ]]; then
    WINDOWS_HOSTS="/mnt/c/Windows/System32/drivers/etc/hosts"
    if ! grep -q "$DOMAIN" "$WINDOWS_HOSTS" 2>/dev/null; then
        echo ""
        echo "🌐 Mapping $DOMAIN to localhost..."
        echo "⚠️  Look at your taskbar! A Windows Administrator prompt (UAC) will pop up."
        echo "   Please click 'Yes' to automatically add the domain to your Windows hosts file."
        # Fire a hidden elevated PowerShell command from WSL to edit the Windows file cleanly
        powershell.exe -Command "Start-Process powershell -Verb RunAs -ArgumentList '-WindowStyle Hidden -Command Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value \"127.0.0.1 $DOMAIN\"'"
        sleep 2
    else
        echo "✅ Domain $DOMAIN is already routed in your Windows hosts file."
    fi
fi

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
# 📥 MAGENTO BASE INSTALLATION
# ==========================================
echo "🔑 Authenticating standard Magento Repo globally (required for create-project)..."
docker-compose exec -T --user nobody web composer config -g http-basic.repo.magento.com "$MAGENTO_PUB_KEY" "$MAGENTO_PRIV_KEY"

if [ ! -f "magento-src/bin/magento" ]; then
    echo "📥 Downloading fresh base Magento 2.4.7-p8..."
    docker-compose exec -T --user nobody web composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition=2.4.7-p8 .
fi

# Lock the credentials into the physical project directory so they persist and apply to all users
echo "🔐 Locking Magento keys into project auth.json..."
docker-compose exec -T --user nobody web composer config http-basic.repo.magento.com "$MAGENTO_PUB_KEY" "$MAGENTO_PRIV_KEY"

if [ ! -f "magento-src/app/etc/env.php" ]; then
    echo "⚙️ Running base Magento setup:install..."
    docker-compose exec -T --user nobody web bin/magento setup:install \
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
# 🔄 OPTION 2: MERGE & UPGRADE EXISTING REPO
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
            echo "🧩 Locking Third-Party Vendor ($V_URL) into project auth.json..."
            docker-compose exec -T --user nobody web composer config http-basic."$V_URL" "$V_PUB" "$V_PRIV"
        done
    fi

    echo "📥 Installing custom Composer dependencies..."
    # Note: Deliberately removing -T so interactive prompts for missing credentials work safely
    docker-compose exec --user nobody web composer install -d /var/www/html

    echo "🔓 Unlocking host-level file permissions to prevent Docker/WSL locks..."
    chmod -R 777 ./magento-src/app/etc 2>/dev/null || true
    chmod 644 ./magento-src/auth.json 2>/dev/null || true

    echo "🧹 Wiping corrupted cache FIRST so the CLI can boot safely..."
    docker-compose exec -T --user root web bash -c "rm -rf var/cache/* var/page_cache/* var/view_preprocessed/* generated/code/* generated/metadata/*"
    docker-compose exec -T --user root web bash -c "mkdir -p generated/code generated/metadata var/cache var/page_cache var/view_preprocessed && chmod -R 777 generated var pub/static app/etc"

    echo "🛡️ Quarantining troublesome modules to protect the build..."
    # 1. LiteMage: Physical move and manual config scrub so it doesn't ghost crash the CLI
    docker-compose exec -T --user root web bash -c "mv app/code/Litespeed /tmp/Litespeed_backup 2>/dev/null || true"
    docker-compose exec -T --user root web sed -i '/Litespeed_Litemage/d' app/etc/config.php 2>/dev/null || true
    
    # 2. Feefo & Phpro: Now that the CLI is healthy, disable them safely
    docker-compose exec -T --user nobody web bin/magento module:disable Feefo_Reviews Phpro_CookieConsent --clear-static-content

    echo "🚀 Running setup:upgrade to register custom modules..."
    docker-compose exec -T --user nobody web bin/magento setup:upgrade
fi

# ==========================================
# 🛠️ MAGENTO COMPILATION (Applies to BOTH options)
# ==========================================
echo "🛠️ Setting Developer Mode..."
docker-compose exec -T --user nobody web bin/magento deploy:mode:set developer

echo "🧱 Compiling Dependency Injection..."
docker-compose exec -T --user nobody web bin/magento setup:di:compile

echo "🎨 Deploying Static Content for $MAGENTO_LANG..."
docker-compose exec -T --user nobody web bin/magento setup:static-content:deploy -f "$MAGENTO_LANG" en_US

# ==========================================
# 🎨 FRONTEND TOOLING (NODE & GRUNT)
# ==========================================
echo "🎨 Setting up Node.js & Grunt for frontend development..."
docker-compose exec -T --user nobody web bash -c "if [ ! -f package.json ]; then cp package.json.sample package.json; fi"
docker-compose exec -T --user nobody web bash -c "if [ ! -f Gruntfile.js ]; then cp Gruntfile.js.sample Gruntfile.js; fi"
docker-compose exec -T --user nobody web npm install

# ==========================================
# ⚙️ FINAL CONFIGURATION
# ==========================================
echo "⚡ Linking Redis and RabbitMQ..."
docker-compose exec -T --user nobody web bin/magento setup:config:set --cache-backend=redis --cache-backend-redis-server=redis --cache-backend-redis-db=0 -n
docker-compose exec -T --user nobody web bin/magento setup:config:set --page-cache=redis --page-cache-redis-server=redis --page-cache-redis-db=1 -n
docker-compose exec -T --user nobody web bin/magento setup:config:set --session-save=redis --session-save-redis-host=redis --session-save-redis-log-level=4 --session-save-redis-db=2 -n
docker-compose exec -T --user nobody web bin/magento setup:config:set --amqp-host=rabbitmq --amqp-port=5672 --amqp-user=guest --amqp-password=guest -n

echo "🧹 Locking Permissions & Clearing Cache..."
docker-compose exec -T --user root web chown -R nobody:nogroup var/ pub/static/ pub/media/ generated/ auth.json || true
docker-compose exec -T --user root web chmod -R 777 var/ pub/static/ pub/media/ generated/ auth.json || true
docker-compose exec -T --user nobody web bin/magento cache:flush

# ==========================================
# 🛠️ DEVELOPER ALIAS SETUP
# ==========================================
echo "🛠️ Configuring WSL Developer Aliases..."
ALIAS_MARKER="# Magento 2 Docker Aliases"

if ! grep -q "$ALIAS_MARKER" ~/.bashrc; then
    cat << 'EOF' >> ~/.bashrc

# Magento 2 Docker Aliases
alias m="docker-compose exec --user nobody web bin/magento"
alias mc="docker-compose exec --user nobody web composer"
alias mcli="docker-compose exec --user nobody web bash"
alias mg="docker-compose exec --user nobody web grunt"
alias mnpm="docker-compose exec --user nobody web npm"
alias mclean="docker-compose exec --user nobody web bash -c 'rm -rf var/cache/* var/page_cache/* var/view_preprocessed/* generated/code/* generated/metadata/* pub/static/frontend/* pub/static/adminhtml/* && bin/magento cache:flush' && docker-compose exec --user root web chmod -R 777 var/ pub/static/ pub/media/ generated/"
EOF
    echo "✅ Aliases added successfully! (Run 'source ~/.bashrc' or restart your terminal to use them)."
else
    echo "✅ Aliases already configured in ~/.bashrc."
fi

# ==========================================
# ⚡ QUARANTINED MODULES OPT-IN
# ==========================================
if [ "$INSTALL_TYPE" == "2" ]; then
    echo ""
    read -p "🚀 Would you like to restore and enable the quarantined modules (LiteMage, Feefo, CookieConsent)? (y/n): " ENABLE_QUARANTINE
    if [[ "$ENABLE_QUARANTINE" =~ ^[Yy]$ ]]; then
        echo "⚡ Restoring LiteMage from /tmp..."
        docker-compose exec -T --user root web bash -c "mv /tmp/Litespeed_backup app/code/Litespeed 2>/dev/null || true"
        
        echo "⚡ Enabling modules in Magento..."
        docker-compose exec -T --user nobody web bin/magento module:enable Litespeed_Litemage Feefo_Reviews Phpro_CookieConsent
        
        echo "⚙️ Running final setup:upgrade to sync restored modules..."
        docker-compose exec -T --user nobody web bin/magento setup:upgrade
        
        echo "🧹 Fixing permissions & flushing cache..."
        docker-compose exec -T --user root web bash -c "chmod -R 777 var/ generated/ pub/static/ app/etc/"
        docker-compose exec -T --user nobody web bin/magento cache:flush
        
        echo "✅ Modules successfully restored and enabled!"
    else
        echo "⏸️ Modules remain safely quarantined for a stable local development environment."
    fi
fi

# ==========================================
# 🎉 FINISH
# ==========================================
FINAL_PMA_PORT=$(grep PMA_PORT .env | cut -d '=' -f 2)
FINAL_RMQ_MGMT=$(grep RMQ_MGMT_PORT .env | cut -d '=' -f 2)
FINAL_MAILPIT=$(grep MAILPIT_UI_PORT .env | cut -d '=' -f 2)

echo "🎉 BOOM! Setup Complete!"
echo "🛒 Storefront: $BASE_URL"
echo "🗄️ phpMyAdmin: http://localhost:$FINAL_PMA_PORT"
echo "🐇 RabbitMQ: http://localhost:$FINAL_RMQ_MGMT"
echo "📬 Mailpit: http://localhost:$FINAL_MAILPIT"
echo "⚙️ LiteSpeed Admin: https://localhost:7080"
