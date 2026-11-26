"""Generate env/xavier/dependency-manifest.json from downloaded wheels.

Records, for every artefact the Xavier locks pin, the actual wheel filename,
distribution name, version, Python/ABI/platform tags, Requires-Python (from the
wheel's METADATA), size and SHA-256, plus which lock(s) use it.

Reproduce (on any machine; nothing is installed):
    for l in bootstrap core sci; do
      awk '/^torch @/{s=1;next} s&&/^[[:space:]]/{next} {s=0;print}' \
        env/xavier/requirements-xavier-$l.lock > /tmp/$l.txt
      pip download --dest WHEELS --no-deps --require-hashes --only-binary=:all: \
        --implementation cp --python-version 38 --abi cp38 \
        --platform manylinux_2_31_aarch64 --platform manylinux2014_aarch64 \
        --platform any -r /tmp/$l.txt
    done
    curl -fLo WHEELS/<torch wheel> <torch URL from requirements-xavier-core.lock>
    python3 -I env/xavier/generate_dependency_manifest.py WHEELS env/xavier

Run with -I (isolated) because WHEELS holds downloaded, untrusted files; this
script only hashes them and reads METADATA as text from the zip.
"""
import email.parser
import hashlib
import json
import os
import re
import sys
import zipfile

LOCKS = ("bootstrap", "core", "sci")


def lock_entries(lock_dir):
    """Map sha256 -> set of lock names that pin it."""
    used = {}
    for name in LOCKS:
        text = open(os.path.join(lock_dir, "requirements-xavier-%s.lock" % name)).read()
        for h in re.findall(r"sha256:([0-9a-f]{64})", text):
            used.setdefault(h, set()).add(name)
    return used


def wheel_info(path):
    fname = os.path.basename(path)
    parts = fname[:-4].split("-")
    if len(parts) == 6:  # build tag present
        name, version, _build, py, abi, plat = parts
    else:
        name, version, py, abi, plat = parts
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    requires_python = None
    with zipfile.ZipFile(path) as zf:
        meta = [n for n in zf.namelist() if n.endswith(".dist-info/METADATA") and n.count("/") == 1]
        if meta:
            msg = email.parser.Parser().parsestr(zf.read(meta[0]).decode("utf-8", "replace"), headersonly=True)
            requires_python = msg.get("Requires-Python")
            name = msg.get("Name", name)
            version = msg.get("Version", version)
    return {
        "filename": fname,
        "name": name,
        "version": version,
        "python_tag": py,
        "abi_tag": abi,
        "platform_tag": plat,
        "requires_python": requires_python,
        "size_bytes": os.path.getsize(path),
        "sha256": h.hexdigest(),
    }


def main(wheel_dir, lock_dir):
    used = lock_entries(lock_dir)
    wheels = []
    for fname in sorted(os.listdir(wheel_dir), key=str.lower):
        if not fname.endswith(".whl"):
            continue
        info = wheel_info(os.path.join(wheel_dir, fname))
        locks = sorted(used.get(info["sha256"], ()))
        if not locks:
            sys.exit("wheel %s is not pinned by any lock" % fname)
        info["locks"] = locks
        wheels.append(info)
    manifest = {
        "description": "Actual wheels pinned by env/xavier locks for Jetson AGX Xavier, JetPack 5.1.6, Python 3.8 (cp38), aarch64, glibc 2.31",
        "target": {"python": "3.8", "abi": "cp38", "platform": "linux_aarch64 / manylinux <= 2_31"},
        "source_compilation_required": False,
        "wheels": wheels,
    }
    out = os.path.join(lock_dir, "dependency-manifest.json")
    with open(out, "w") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
        fh.write("\n")
    print("wrote %s (%d wheels)" % (out, len(wheels)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
