# Magento 2 Local Development Environment (Docker + WSL2)

This repository contains the automated setup script and Docker orchestration files required to spin up a production-ready Magento 2 environment locally. 

By utilizing Docker inside Windows Subsystem for Linux (WSL 2), we achieve native Linux filesystem performance while developing on a Windows machine.

## 🛑 Prerequisites

Before running the setup script, you must ensure your Windows machine is prepped with WSL2 and Docker.

1. **Install WSL 2 & Ubuntu:**
   * Open PowerShell as Administrator and run: `wsl --install`
   * Restart your computer.
   * Open the **Ubuntu** app from your Start Menu to initialize it and set up your UNIX username/password.
2. **Install Docker Desktop:**
   * Download and install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop).
   * Go to **Settings (Gear Icon) > General** and ensure **Use the WSL 2 based engine** is checked.
   * Go to **Settings > Resources > WSL Integration** and turn the toggle **ON** for your installed Ubuntu distribution.

3. **Get Your Magento Access Keys:**
   * Log into [marketplace.magento.com](https://marketplace.magento.com/).
   * Go to **My Profile > Access Keys**.
   * Have your **Public Key** and **Private Key** ready. (If the project uses third-party modules like Amasty or Mageplaza, have those composer credentials ready as well).

---

## 🚀 Installation: The "One-Liner"

Do **not** run this in Windows Command Prompt or PowerShell. 
Open your **Ubuntu (WSL)** terminal and paste this single command:

```bash
mkdir -p ~/Sites/magentocd && cd $_ && bash -c "$(curl -fsSL [https://raw.githubusercontent.com/Chris-Weeks/docker-magento-setup/main/install.sh](https://raw.githubusercontent.com/Chris-Weeks/docker-magento-setup/main/install.sh))"
```

### What this script does automatically:
1. Downloads the necessary Docker and configuration files.
2. Prompts you for your Magento/Git credentials.
3. Builds a lightweight Debian-based `php:8.2-apache` container stack.
4. Clones the repository (or installs a fresh Magento instance).
5. Installs Composer dependencies.
6. Runs the Magento database installation and connects Redis/RabbitMQ.
7. Installs daily-use developer aliases into your terminal.

---

## 🛠️ Everyday Developer Workflow

To make interacting with the Docker containers painless, the setup script automatically installed several aliases into your `~/.bashrc` profile. You can run these from anywhere inside the `~/Sites/magentocd` directory:

* **`m`** - The standard Magento CLI. 
  * *Example:* `m cache:flush` or `m setup:upgrade`
* **`mc`** - The Composer CLI.
  * *Example:* `mc require vendor/module`
* **`mcli`** - Drops you directly into the web container's bash shell.
* **`mclean`** - **Use this when switching Git branches!** It safely wipes generated code, view_preprocessed, and caches, ensuring your new branch compiles cleanly without fatal errors.

---

## 🐛 Debugging with Xdebug

Xdebug is pre-installed but disabled by default to keep the site running at lightning speed. When you need to set a breakpoint in PhpStorm or VS Code, you can toggle it on and off instantly.

In your terminal (inside the project root), run:
```bash
./toggle-xdebug.sh
```
*This script safely renames the configuration file and gracefully restarts Apache in less than a second.*

---

## 🌐 Service URLs
Once the setup is complete, your local services are mapped to the following ports:

* **Storefront & Admin:** `http://localhost:8000`
* **phpMyAdmin:** `http://localhost:8081` *(User: `root` / Pass: `rootpassword`)*
* **RabbitMQ:** `http://localhost:15672` *(User: `guest` / Pass: `guest`)*
* **Mailpit (Local Email Catcher):** `http://localhost:8025`
