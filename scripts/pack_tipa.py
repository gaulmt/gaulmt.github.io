import os
import sys
import shutil
import zipfile

def pack_tipa(staged_app, out_tipa, out_ipa=None):
    if not os.path.isdir(staged_app):
        raise FileNotFoundError(f"Staged app directory does not exist: {staged_app}")
    
    app_name = os.path.basename(staged_app.rstrip('/\\'))
    if not app_name.endswith('.app'):
        app_name += '.app'

    os.makedirs(os.path.dirname(os.path.abspath(out_tipa)), exist_ok=True)
    with zipfile.ZipFile(out_tipa, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(staged_app):
            rel = os.path.relpath(root, staged_app)
            for f in sorted(files):
                fpath = os.path.join(root, f)
                if rel == '.':
                    arc = f"Payload/{app_name}/{f}"
                else:
                    arc = f"Payload/{app_name}/{rel}/{f}".replace('\\', '/')
                
                # Ensure UNIX file permissions in zip header
                zinfo = zipfile.ZipInfo(arc)
                zinfo.compress_type = zipfile.ZIP_DEFLATED
                # If executable Mach-O binary
                if not f.endswith(('.png', '.plist', '.wav', '.json', '.txt', '.strings', '.html', '.css', '.js')):
                    zinfo.external_attr = 0o755 << 16
                else:
                    zinfo.external_attr = 0o644 << 16
                
                with open(fpath, 'rb') as fp:
                    zf.writestr(zinfo, fp.read())

    print(f"[OK] Created {out_tipa} ({os.path.getsize(out_tipa):,} bytes)")

    if out_ipa:
        shutil.copyfile(out_tipa, out_ipa)
        print(f"[OK] Copied to {out_ipa}")

    with zipfile.ZipFile(out_tipa, 'r') as zf:
        names = zf.namelist()
        expected_binary = f"Payload/{app_name}/NowEvent"
        matched = [n for n in names if n.lower() == expected_binary.lower()]
        if not matched:
            raise RuntimeError(f"FATAL: Missing binary {expected_binary} in package! Files: {names[:10]}")
        bin_info = zf.getinfo(matched[0])
        print(f"[VERIFIED] Found main binary {matched[0]} ({bin_info.file_size:,} bytes, compressed: {bin_info.compress_size:,} bytes)")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: pack_tipa.py <staged_app_path> <out_tipa_path> [out_ipa_path]")
        sys.exit(1)
    pack_tipa(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
