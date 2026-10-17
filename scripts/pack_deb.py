import os
import sys
import io
import tarfile

def pack_deb(src_dir, out_deb):
    deb_binary = b'2.0\n'

    # 1. control.tar.gz
    ctrl_buf = io.BytesIO()
    with tarfile.open(fileobj=ctrl_buf, mode='w:gz', format=tarfile.GNU_FORMAT) as tar:
        debian_dir = os.path.join(src_dir, 'DEBIAN')
        if not os.path.isdir(debian_dir):
            raise RuntimeError(f"Missing DEBIAN directory in {src_dir}")
        for item in sorted(os.listdir(debian_dir)):
            full = os.path.join(debian_dir, item)
            ti = tar.gettarinfo(full, arcname=f'./{item}')
            ti.uid = 0
            ti.gid = 0
            ti.uname = 'root'
            ti.gname = 'root'
            if item in ('postinst', 'prerm', 'postrm', 'preinst'):
                ti.mode = 0o755
            else:
                ti.mode = 0o644
            if os.path.isfile(full):
                with open(full, 'rb') as f:
                    tar.addfile(ti, f)
            else:
                tar.addfile(ti)
    ctrl_data = ctrl_buf.getvalue()

    # 2. data.tar.gz
    data_buf = io.BytesIO()
    with tarfile.open(fileobj=data_buf, mode='w:gz', format=tarfile.GNU_FORMAT) as tar:
        for root, dirs, files in os.walk(src_dir):
            rel = os.path.relpath(root, src_dir)
            if rel == '.' or rel == 'DEBIAN' or rel.startswith('DEBIAN' + os.sep):
                continue
            arc_dir = rel.replace('\\', '/')
            ti = tar.gettarinfo(root, arcname=f'./{arc_dir}')
            ti.uid = 0
            ti.gid = 0
            ti.uname = 'root'
            ti.gname = 'root'
            ti.mode = 0o755
            tar.addfile(ti)
            for f in sorted(files):
                fpath = os.path.join(root, f)
                f_rel = os.path.relpath(fpath, src_dir).replace('\\', '/')
                ti_f = tar.gettarinfo(fpath, arcname=f'./{f_rel}')
                ti_f.uid = 0
                ti_f.gid = 0
                ti_f.uname = 'root'
                ti_f.gname = 'root'
                # Executable binary inside .app
                if not f.endswith(('.png', '.plist', '.wav', '.json', '.txt', '.strings', '.html', '.css', '.js')):
                    ti_f.mode = 0o755
                else:
                    ti_f.mode = 0o644
                with open(fpath, 'rb') as fh:
                    tar.addfile(ti_f, fh)
    data_data = data_buf.getvalue()

    # 3. ar archive (.deb)
    def make_ar_header(name, size):
        return (f"{name:<16}" + f"{0:<12}" + f"{0:<6}" + f"{0:<6}" + f"{0o100644:<8o}" + f"{size:<10}" + '`\n').encode('ascii')

    os.makedirs(os.path.dirname(os.path.abspath(out_deb)), exist_ok=True)
    with open(out_deb, 'wb') as deb:
        deb.write(b'!<arch>\n')
        
        # debian-binary
        deb.write(make_ar_header('debian-binary', len(deb_binary)))
        deb.write(deb_binary)
        if len(deb_binary) % 2 != 0:
            deb.write(b'\n')
            
        # control.tar.gz
        deb.write(make_ar_header('control.tar.gz', len(ctrl_data)))
        deb.write(ctrl_data)
        if len(ctrl_data) % 2 != 0:
            deb.write(b'\n')
            
        # data.tar.gz
        deb.write(make_ar_header('data.tar.gz', len(data_data)))
        deb.write(data_data)
        if len(data_data) % 2 != 0:
            deb.write(b'\n')

    print(f"[OK] Successfully built {out_deb} ({os.path.getsize(out_deb)} bytes)")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: pack_deb.py <source_dir> <output_deb>")
        sys.exit(1)
    pack_deb(sys.argv[1], sys.argv[2])
