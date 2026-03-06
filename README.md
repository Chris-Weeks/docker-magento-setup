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
mkdir -p ~/Sites/magentocd && cd $_ && bash -c "$(curl -fsSL https://raw.githubusercontent.com/Chris-Weeks/docker-magento-setup/main/install.sh)"
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

---

## 💻 Setting up PhpStorm for Docker Development

To get the most out of PhpStorm (like code completion, syntax highlighting, and debugging), you need to tell it to use the PHP engine running *inside* your Docker container, rather than looking for one on your local machine.

### 1. Open the Project Correctly
Since the files live in WSL, you should open the project via the WSL file system.
* Open PhpStorm.
* Click **Open**.
* Navigate to your WSL directory: `\\wsl$\Ubuntu\home\YOUR_USERNAME\Sites\magentocd\magento-src` (or open it directly from the WSL terminal by typing `phpstorm.exe .` inside the folder).

### 2. Configure the Docker CLI Interpreter
This allows PhpStorm to run PHP commands (like Code Sniffer or PHPUnit) using the container's environment.

1. Go to **File > Settings > PHP**.
2. Next to the **CLI Interpreter** dropdown, click the `...` button.
3. Click the `+` icon at the top left and select **From Docker, Vagrant, VM, WSL, Remote...**
4. Select **Docker Compose**.
5. Set the **Server** to `Docker` (or set up a new Docker connection if prompted).
6. Set the **Configuration file(s)** to your `docker-compose.yml` file.
7. Set the **Service** to `web`.
8. Click **OK**. PhpStorm will briefly scan the container and detect PHP 8.2 and Xdebug.

### 3. Configure Path Mappings (Crucial for Xdebug)
PhpStorm needs to know how the files on your Windows machine map to the files inside the Linux container.

1. Go to **File > Settings > PHP > Servers**.
2. Click the `+` icon to add a new server.
3. **Name:** `magento.test` (or `localhost` depending on your Base URL setup).
4. **Host:** `magento.test` (or `localhost`).
5. **Port:** `8000`.
6. Check the box that says **Use path mappings**.
7. In the file tree below, find your local project root (`.../magentocd/magento-src`).
8. In the column next to it (Absolute path on the server), type: `/var/www/html`.
9. Click **Apply** and **OK**.


### 4. Catching Breakpoints with Xdebug
Xdebug is pre-configured to communicate back to your host machine via port `9003`. 

1. In PhpStorm, ensure the "Listen for PHP Debug Connections" button (the little phone icon in the top right toolbar) is clicked and turned **green**.
2. Open your WSL terminal and run the toggle script to turn Xdebug on:
   ```bash
   ./toggle-xdebug.sh
3. Set a breakpoint in your code (e.g., pub/index.php).
4. Refresh your browser. PhpStorm should immediately flash and pause execution at your breakpoint!

(Note: Don't forget to run ./toggle-xdebug.sh again to turn it off when you are done debugging, as Xdebug slows down page load times significantly).

