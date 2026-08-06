#!/bin/bash
# FinanceApp 一鍵更新腳本
# 用法：./update.sh
# 功能：拉取最新代碼 → 清理 Xcode 快取 → 開啟項目

set -e

# 切換到腳本所在目錄（無論從哪裡執行都能正確定位）
cd "$(dirname "$0")"

echo "📥 正在拉取最新代碼..."
git pull

echo "🧹 正在清理 DerivedData 快取..."
rm -rf ~/Library/Developer/Xcode/DerivedData/FinanceApp-* 2>/dev/null || true

echo "🚀 正在開啟 Xcode..."
open FinanceApp.xcodeproj

echo "✅ 完成！在 Xcode 中按 Cmd + R 即可運行。"
