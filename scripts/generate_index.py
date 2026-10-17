import os
import sys

def generate_index(stage_dir):
    html_content = """<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <title>gaulmt Official Sileo Repo & Products</title>
  <link rel="icon" type="image/png" href="CydiaIcon@3x.png">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #0d0f12;
      color: #e6edf3;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      padding: 24px 16px 48px;
      min-height: 100vh;
    }
    .container {
      max-width: 520px;
      margin: 0 auto;
    }
    .header-card {
      background: linear-gradient(145deg, #161b22, #0d1117);
      border: 1px solid #30363d;
      border-radius: 24px;
      padding: 28px 20px;
      text-align: center;
      box-shadow: 0 12px 30px rgba(0,0,0,0.5);
      margin-bottom: 24px;
    }
    .repo-logo {
      width: 80px;
      height: 80px;
      border-radius: 20px;
      margin: 0 auto 14px;
      display: block;
      border: 2px solid #e5c07b;
      box-shadow: 0 4px 16px rgba(229, 192, 123, 0.25);
    }
    h1 { font-size: 26px; font-weight: 800; color: #fff; margin-bottom: 6px; }
    .sub { color: #8b949e; font-size: 14px; margin-bottom: 20px; }
    .btn-grid {
      display: flex;
      flex-direction: column;
      gap: 10px;
      margin-bottom: 16px;
    }
    .btn {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      text-decoration: none;
      padding: 14px 18px;
      border-radius: 14px;
      font-weight: 700;
      font-size: 15px;
      transition: transform 0.15s ease, opacity 0.15s ease;
    }
    .btn:active { transform: scale(0.98); }
    .btn-sileo { background: #e5c07b; color: #1a160d; }
    .btn-zebra { background: #21262d; color: #58a6ff; border: 1px solid #30363d; }
    .url-card {
      background: #0b0d0e;
      border: 1px dashed #30363d;
      border-radius: 12px;
      padding: 12px;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 13px;
      color: #e5c07b;
      word-break: break-all;
      user-select: all;
    }
    .section-title {
      font-size: 18px;
      font-weight: 700;
      color: #fff;
      margin: 28px 0 14px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .product-card {
      background: #161b22;
      border: 1px solid #30363d;
      border-radius: 18px;
      padding: 18px;
      margin-bottom: 16px;
      transition: border-color 0.2s ease;
    }
    .product-card:hover { border-color: #58a6ff; }
    .product-header {
      display: flex;
      align-items: center;
      gap: 14px;
      margin-bottom: 12px;
    }
    .product-icon {
      width: 52px;
      height: 52px;
      border-radius: 14px;
      object-fit: cover;
      border: 1px solid #30363d;
    }
    .product-title {
      font-size: 17px;
      font-weight: 700;
      color: #fff;
    }
    .product-version {
      font-size: 12px;
      color: #8b949e;
    }
    .badge-row {
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
      margin-bottom: 12px;
    }
    .badge {
      font-size: 11px;
      padding: 3px 8px;
      border-radius: 6px;
      font-weight: 600;
    }
    .badge-ios { background: rgba(56, 139, 253, 0.15); color: #58a6ff; border: 1px solid rgba(56, 139, 253, 0.4); }
    .badge-android { background: rgba(46, 160, 67, 0.15); color: #3fb950; border: 1px solid rgba(46, 160, 67, 0.4); }
    .badge-gold { background: rgba(229, 192, 123, 0.15); color: #e5c07b; border: 1px solid rgba(229, 192, 123, 0.4); }
    .product-desc {
      font-size: 13px;
      color: #c9d1d9;
      line-height: 1.5;
      margin-bottom: 14px;
    }
    .product-actions {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }
    .action-link {
      flex: 1;
      min-width: 130px;
      text-align: center;
      text-decoration: none;
      font-size: 13px;
      font-weight: 600;
      padding: 10px 14px;
      border-radius: 10px;
      border: 1px solid #30363d;
      color: #e6edf3;
      background: #21262d;
      transition: all 0.15s ease;
    }
    .action-link:hover {
      background: #30363d;
      border-color: #8b949e;
    }
    .action-link.primary {
      background: #238636;
      border-color: #2ea043;
      color: #fff;
    }
    .action-link.primary:hover {
      background: #2ea043;
    }
    footer {
      text-align: center;
      margin-top: 36px;
      font-size: 12px;
      color: #6e7681;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header-card">
      <img class="repo-logo" src="CydiaIcon@3x.png" alt="gaulmt Repo Logo">
      <h1>gaulmt Official Repo</h1>
      <div class="sub">Kho ứng dụng & Tweak Sileo / Zebra chính thức</div>

      <div class="btn-grid">
        <a class="btn btn-sileo" href="sileo://source/https://gaulmt.github.io/">
          <span>➕</span> Thêm nguồn vào Sileo
        </a>
        <a class="btn btn-zebra" href="zbra://sources/add/https://gaulmt.github.io/">
          <span>➕</span> Thêm nguồn vào Zebra
        </a>
      </div>

      <div class="url-card">https://gaulmt.github.io/</div>
    </div>

    <div class="section-title">
      <span>📦</span> Danh mục sản phẩm trong kho
    </div>

    <!-- Product 1: quang lam marketing (ZTech) -->
    <div class="product-card">
      <div class="product-header">
        <img class="product-icon" src="CydiaIcon@3x.png" alt="ZTech Icon">
        <div>
          <div class="product-title">quang lam marketing (ZTech)</div>
          <div class="product-version">Phiên bản 5.6.2 · iOS 12.0 - 17.0+</div>
        </div>
      </div>
      <div class="badge-row">
        <span class="badge badge-gold">Universal Spoofing</span>
        <span class="badge badge-ios">Rootless</span>
        <span class="badge badge-ios">Rootful</span>
        <span class="badge badge-gold">TrollStore</span>
      </div>
      <div class="product-desc">
        Bộ công cụ đổi thông số máy 37 dòng iPhone không sót dấu vết máy thật trong Zalo & AIDA64. Hỗ trợ Respring tự động và MobileGestalt hook.
      </div>
      <div class="product-actions">
        <a class="action-link" href="sileo://package/com.ztech.devicechanger">Cài trên Sileo</a>
        <a class="action-link" href="apple-magnifier://install?url=https://gaulmt.github.io/downloads/gaulmt_Tech_TrollStore.tipa">TrollStore (.tipa)</a>
        <a class="action-link" href="debs/gaulmt_Tech_Rootless_arm64.deb">Tải .deb</a>
      </div>
    </div>

    <!-- Product 2: Now Event Notification -->
    <div class="product-card">
      <div class="product-header">
        <img class="product-icon" src="icons/now_event.png" alt="Now Event Icon">
        <div>
          <div class="product-title">Now Event Notification (IUH)</div>
          <div class="product-version">Phiên bản 2.1.0 · Đăng tải bởi gaulmt</div>
        </div>
      </div>
      <div class="badge-row">
        <span class="badge badge-android">Android (.apk)</span>
        <span class="badge badge-ios">iOS Sileo (.deb)</span>
        <span class="badge badge-gold">Thời gian thực</span>
      </div>
      <div class="product-desc">
        Ứng dụng theo dõi thông báo sự kiện Đoàn Thanh niên IUH tức thì. Tự động tính toán tỷ lệ slot đăng ký (100%, 50%, &lt;5%) và cảnh báo slot sắp hết.
      </div>
      <div class="product-actions">
        <a class="action-link primary" href="downloads/NowEventNotification.apk" download>
          ⚡ Tải APK Android
        </a>
        <a class="action-link" href="sileo://package/com.gaulmt.noweventnotification">
          Cài trên Sileo
        </a>
        <a class="action-link" href="debs/NowEventNotification_2.1_iphoneos-arm.deb">
          Tải .deb iOS
        </a>
      </div>
    </div>

    <footer>
      © 2026 gaulmt Official Repository · Tự động build & đồng bộ bởi GitHub Actions
    </footer>
  </div>
</body>
</html>
"""
    out_path = os.path.join(stage_dir, 'index.html')
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(html_content)
    print(f"Generated index.html at: {out_path}")

if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else '.'
    generate_index(target)
