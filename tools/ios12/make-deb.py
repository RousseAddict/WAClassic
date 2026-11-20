#!/usr/bin/env python3
"""Pack a dpkg layout folder into a .deb, without dpkg-deb (macOS has none).

Usage: python3 -I make-deb.py <layout-dir> <output.deb>

<layout-dir>/DEBIAN holds control + maintainer scripts, everything else is the
filesystem payload. Files are stored as root:wheel. Directories, the scripts in
DEBIAN and anything already executable on disk get 0755, the rest 0644.
"""
import io
import os
import sys
import tarfile
import time


def build_tar(root, include, exclude_top=None):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz", format=tarfile.GNU_FORMAT) as tar:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames.sort()
            rel_dir = os.path.relpath(dirpath, root)
            if exclude_top and rel_dir.split(os.sep)[0] == exclude_top:
                dirnames[:] = []
                continue
            entries = [(dirpath, True)] + [(os.path.join(dirpath, f), False) for f in sorted(filenames)]
            for path, is_dir in entries:
                rel = os.path.relpath(path, root)
                if not include(rel):
                    continue
                name = "./" if rel == "." else "./" + rel.replace(os.sep, "/")
                info = tarfile.TarInfo(name)
                info.uid = info.gid = 0
                info.uname, info.gname = "root", "wheel"
                info.mtime = int(time.time())
                if is_dir:
                    info.type, info.mode = tarfile.DIRTYPE, 0o755
                    tar.addfile(info)
                else:
                    if os.path.islink(path):
                        raise SystemExit(f"symlinks are not supported: {rel}")
                    info.size = os.path.getsize(path)
                    info.mode = 0o755 if os.access(path, os.X_OK) else 0o644
                    with open(path, "rb") as fh:
                        tar.addfile(info, fh)
    return buf.getvalue()


def ar_member(name, data):
    header = (
        f"{name:<16}"
        f"{int(time.time()):<12}"
        f"{0:<6}{0:<6}"
        f"{'100644':<8}"
        f"{len(data):<10}"
        "`\n"
    ).encode()
    assert len(header) == 60
    return header + data + (b"\n" if len(data) % 2 else b"")


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    layout, out = sys.argv[1], sys.argv[2]
    control_dir = os.path.join(layout, "DEBIAN")
    if not os.path.isfile(os.path.join(control_dir, "control")):
        raise SystemExit(f"missing {control_dir}/control")
    control = build_tar(control_dir, lambda rel: True)
    data = build_tar(layout, lambda rel: True, exclude_top="DEBIAN")
    with open(out, "wb") as fh:
        fh.write(b"!<arch>\n")
        fh.write(ar_member("debian-binary", b"2.0\n"))
        fh.write(ar_member("control.tar.gz", control))
        fh.write(ar_member("data.tar.gz", data))
    print(f"wrote {out} ({os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
