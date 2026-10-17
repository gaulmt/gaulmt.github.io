import os
import sys
import hashlib

def generate_release(stage_dir):
    files = ['Packages', 'Packages.gz', 'Packages.bz2', 'Packages.xz', 'Packages.zst']
    valid_files = [f for f in files if os.path.isfile(os.path.join(stage_dir, f))]

    def get_hash(fn, algo):
        full_path = os.path.join(stage_dir, fn)
        h = getattr(hashlib, algo)()
        with open(full_path, 'rb') as f:
            while chunk := f.read(65536):
                h.update(chunk)
        return h.hexdigest(), os.path.getsize(full_path)

    header = """Origin: gaulmt Official Sileo Repo
Label: gaulmt Repo
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm iphoneos-arm64 iphoneos-arm64e
Components: main
Description: Kho ung dung, tweak & san pham gaulmt tren Sileo & Zebra
"""

    for algo_name, algo_key in [('MD5Sum', 'md5'), ('SHA1', 'sha1'), ('SHA256', 'sha256')]:
        header += f"{algo_name}:\n"
        for fn in valid_files:
            digest, size = get_hash(fn, algo_key)
            header += f" {digest} {size} {fn}\n"

    release_path = os.path.join(stage_dir, 'Release')
    with open(release_path, 'w', encoding='utf-8') as f:
        f.write(header)
    print(f"Generated Release file at: {release_path}")

if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else '.'
    generate_release(target)
