#!/bin/bash
# Helper: cài apt package từ trong container (cần sudo)
set -e
echo "📦 Đang cài đặt: $@"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends "$@"
sudo rm -rf /var/lib/apt/lists/*
echo "✅ Đã cài xong: $@"
