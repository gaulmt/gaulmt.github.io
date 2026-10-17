@echo off
chcp 65001 >nul
title Đăng Sản Phẩm Lên Kho Sileo (gaulmt.github.io)
cd /d "%~dp0"

echo ================================================================
echo   gaulmt Sileo Repo - Tự động đẩy sản phẩm lên kho Sileo
echo ================================================================
echo.
echo Thư mục 'packages/' chứa các gói .deb:
dir /b packages\*.deb 2>nul
echo.
echo Thư mục 'downloads/' chứa file tải trực tiếp (.tipa, .apk):
dir /b downloads\* 2>nul
echo.

git status --short
echo.
echo Bấm phím bất kỳ để Commit và Push lên GitHub Actions tự động cập nhật kho Sileo...
pause >nul

git add .
git commit -m "feat: cap nhat danh muc san pham va deploy Sileo repo [auto]"
git push origin main

echo.
echo ================================================================
echo Đã push code lên GitHub thành công!
echo GitHub Action 'deploy-sileo-repo' đang chạy ngầm trên GitHub.
echo Trong vòng 30-45 giây, kho Sileo và trang web https://gaulmt.github.io/
echo sẽ tự động cập nhật sản phẩm mới nhất!
echo ================================================================
echo.
pause
