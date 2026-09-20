#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt install -y \
  build-essential \
  cmake \
  ninja-build \
  qt6-base-dev \
  qt6-declarative-dev \
  qt6-declarative-dev-tools \
  qt6-tools-dev \
  qt6-tools-dev-tools \
  libqt6svg6 \
  libqt6sql6-sqlite \
  qml6-module-qtquick \
  qml6-module-qtquick-controls \
  qml6-module-qtquick-dialogs \
  qml6-module-qtquick-layouts \
  openssh-client \
  curl \
  sshpass \
  zip \
  unzip \
  libsecret-tools

# RDP is optional at runtime.
if apt-cache show freerdp3-x11 >/dev/null 2>&1; then
  sudo apt install -y freerdp3-x11
elif apt-cache show freerdp-x11 >/dev/null 2>&1; then
  sudo apt install -y freerdp-x11
else
  echo "Warning: FreeRDP X11 package was not found. SSH/local terminal still work." >&2
fi

echo "Dependencies installed. Run: ./scripts/run.sh"
