#!/bin/bash
set -euxo pipefail
if [ ! -f /etc/os-release ]; then
    echo "Unknown OS"
    exit 1
fi
. /etc/os-release
echo "ID=$ID"
echo "ID_LIKE=${ID_LIKE:-}"
if [[ "$EUID" -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi
if command -v apt >/dev/null 2>&1; then
    PKG="apt"
elif command -v dnf >/dev/null 2>&1; then
    PKG="dnf"
elif command -v pacman >/dev/null 2>&1; then
    PKG="pacman"
else
    echo "Unsupported package manager"
    exit 1
fi
echo "PKG=$PKG"
install_apt() {
    DISTRO_CODENAME="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || true)}"
    if [[ -z "$DISTRO_CODENAME" ]]; then
        echo "Could not determine distro codename"
        exit 1
    fi
    echo "CODENAME=$DISTRO_CODENAME"
    export DEBIAN_FRONTEND=noninteractive
    $SUDO apt update -y
    $SUDO apt install -y ca-certificates curl gnupg lsb-release
    $SUDO mkdir -p /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$ID/gpg" | $SUDO gpg --dearmor --yes --batch -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
    ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
    $SUDO rm -f /etc/apt/sources.list.d/docker.list
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $DISTRO_CODENAME stable" | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
    $SUDO apt update -y
    if apt-cache policy docker-ce | grep -q 'Candidate: (none)'; then
        echo "Docker repo not available for this distro/codename"
        exit 1
    fi
    apt-cache policy docker-ce | awk 'NR<=10'
    $SUDO apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
}
install_dnf() {
    $SUDO dnf -y install dnf-plugins-core

    $SUDO dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

    $SUDO dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    $SUDO systemctl enable --now docker || true
}
install_pacman() {
    $SUDO pacman -Sy --noconfirm docker docker-compose

    $SUDO systemctl enable --now docker || true
}
case "$PKG" in
    apt)
        install_apt
        ;;
    dnf)
        install_dnf
        ;;
    pacman)
        install_pacman
        ;;
esac
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker installation failed"
    exit 1
fi
docker --version
if $SUDO docker info >/dev/null 2>&1; then
    echo "Docker daemon is running"
else
    echo "⚠️ Docker installed, but daemon not running (this can be normal)"
fi
if $SUDO docker run --rm hello-world >/dev/null 2>&1; then
    echo "Docker fully working (containers run successfully)"
else
    echo "⚠️ Docker installed, but cannot run containers"
fi
if [[ -n "${USER:-}" && "$USER" != "root" ]]; then
    $SUDO usermod -aG docker "$USER" || true
fi
echo "✅ Docker installed successfully."
echo "ℹ️  Log out and back in (or run: newgrp docker) to use Docker without sudo."