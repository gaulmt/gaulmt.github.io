import os, tarfile, io, shutil

# 1. control content
control_content = """Package: com.gaulmt.noweventnotification
Name: Now Event Notification (IUH)
Version: 2.1.0
Architecture: iphoneos-arm
Description: Ung dung theo doi su kien va thong bao Doan Thanh nien IUH truc tuyen danh cho sinh vien.
Maintainer: Nguyen Dang Duong <lmtgau@gmail.com>
Author: Nguyen Dang Duong & Le Phuoc Tai
Section: Utilities
Icon: https://gaulmt.github.io/icons/now_event.png
SileoDepiction: https://gaulmt.github.io/depictions/com.gaulmt.noweventnotification.json
Depiction: https://gaulmt.github.io/
""".encode('utf-8')

control_tar_io = io.BytesIO()
with tarfile.open(fileobj=control_tar_io, mode='w:gz') as tar:
    ti = tarfile.TarInfo('control')
    ti.size = len(control_content)
    ti.mode = 0o644
    tar.addfile(ti, io.BytesIO(control_content))

# 2. data.tar.gz
data_tar_io = io.BytesIO()
with tarfile.open(fileobj=data_tar_io, mode='w:gz') as tar:
    app_plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>launch</string>
    <key>CFBundleIdentifier</key>
    <string>com.gaulmt.noweventnotification</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>IUH Events</string>
    <key>CFBundleDisplayName</key>
    <string>IUH Sự Kiện</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.1.0</string>
    <key>CFBundleVersion</key>
    <string>2.1.0</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
</dict>
</plist>""".encode('utf-8')

    ti = tarfile.TarInfo('Applications/NowEventNotification.app/Info.plist')
    ti.size = len(app_plist)
    ti.mode = 0o644
    tar.addfile(ti, io.BytesIO(app_plist))

    icon_path = 'c:/Users/DUong/Documents/gaulmt.github.io/icons/now_event.png'
    if os.path.exists(icon_path):
        with open(icon_path, 'rb') as f:
            icon_data = f.read()
        ti = tarfile.TarInfo('Applications/NowEventNotification.app/icon.png')
        ti.size = len(icon_data)
        ti.mode = 0o644
        tar.addfile(ti, io.BytesIO(icon_data))

    launcher = b'#!/bin/sh\nopen https://taile-home.tailb889f1.ts.net/iuh\n'
    ti = tarfile.TarInfo('Applications/NowEventNotification.app/launch')
    ti.size = len(launcher)
    ti.mode = 0o755
    tar.addfile(ti, io.BytesIO(launcher))

# 3. ar archive (.deb)
def make_ar_header(name, size):
    return (name.ljust(16) + '0'.ljust(12) + '0'.ljust(6) + '0'.ljust(6) + '100644'.ljust(8) + str(size).ljust(10) + '`\n').encode('ascii')

deb_path = 'c:/Users/DUong/Documents/gaulmt.github.io/packages/NowEventNotification_2.1_iphoneos-arm.deb'

with open(deb_path, 'wb') as deb:
    deb.write(b'!<arch>\n')
    
    # debian-binary
    deb.write(make_ar_header('debian-binary', 4))
    deb.write(b'2.0\n')
    
    # control.tar.gz
    cg = control_tar_io.getvalue()
    deb.write(make_ar_header('control.tar.gz', len(cg)))
    deb.write(cg)
    if len(cg) % 2 != 0: deb.write(b'\n')
    
    # data.tar.gz
    dg = data_tar_io.getvalue()
    deb.write(make_ar_header('data.tar.gz', len(dg)))
    deb.write(dg)
    if len(dg) % 2 != 0: deb.write(b'\n')

print('Successfully created:', deb_path, 'Size:', os.path.getsize(deb_path))
