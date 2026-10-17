import os
import sys

def verify_packages(build_out):
    pkgs = [
        'NowEventNotification_Rootful_arm.deb',
        'NowEventNotification_Rootless_arm64.deb',
        'NowEventNotification.tipa',
        'NowEventNotification.ipa'
    ]
    missing = []
    too_small = []
    for p in pkgs:
        full = os.path.join(build_out, p)
        if not os.path.isfile(full):
            missing.append(p)
            continue
        sz = os.path.getsize(full)
        if sz < 50000:
            too_small.append((p, sz))
            continue
        print(f"[OK] Package {p}: {sz:,} bytes")

    if missing:
        raise RuntimeError(f"FATAL: Missing packages: {missing}")
    if too_small:
        raise RuntimeError(f"FATAL: Packages too small (< 50KB): {too_small}")
    
    print("[ALL OK] All 4 packages successfully validated!")

if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else 'build_out'
    verify_packages(target)
