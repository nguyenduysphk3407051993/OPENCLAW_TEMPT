#!/bin/bash
# Helper: cài npm global package runtime
set -e
echo "📦 Đang cài NPM package: $@"
sudo npm install -g "$@"
echo "✅ Đã cài xong: $@"
