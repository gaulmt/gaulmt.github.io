import sys

def prep_rootless(src, dst):
    with open(src, 'r', encoding='utf-8') as f:
        content = f.read()
    content = content.replace('com.gaulmt.noweventnotification', 'com.gaulmt.noweventnotification.rootless')
    content = content.replace('Now Event Notification (IUH)', 'Now Event Notification (Rootless)')
    content = content.replace('Architecture: iphoneos-arm', 'Architecture: iphoneos-arm64')
    content = content.replace('Depends: firmware (>= 14.0)', 'Depends: firmware (>= 14.0), ellekit')
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"[OK] Prepared rootless control at {dst}")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: prep_rootless_control.py <src_control> <dst_control>")
        sys.exit(1)
    prep_rootless(sys.argv[1], sys.argv[2])
