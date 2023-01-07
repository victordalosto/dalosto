#!/bin/bash

# Updates and upgrades ubuntu
bash bin/ubuntu_update.sh

# Install main packages
bash packages/ubuntu_packages.sh

# Install VSCODE extensions

# Install VSCODE settings and keybindings
bash bin/vscode_settings.sh
