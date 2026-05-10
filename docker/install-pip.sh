#!/bin/bash
# Helper: cài python package runtime
set -e
echo "🐍 Đang cài Python package: $@"
pip3 install --break-system-packages "$@"
echo "✅ Đã cài xong: $@"
