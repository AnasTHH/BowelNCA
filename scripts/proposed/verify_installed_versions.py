"""PROPOSED - NOT APPROVED. Verify installed distribution versions against the manifest.

Run by scripts/proposed/install_xavier_env.sh inside the new venv:

    python -I verify_installed_versions.py --manifest env/xavier/dependency-manifest.json \
        --stage core|sci [--site DIR]

For every wheel the manifest assigns to the stage (bootstrap + core, or
bootstrap + sci), the installed distribution's version is read with
importlib.metadata and compared, after PEP 440 normalization, with the
manifest version. This does not depend on how ``pip freeze`` prints an entry:
a wheel installed from a local file appears there as a PEP 610 direct reference
(``torch @ file:///...``), not ``torch==<version>``.

Prints a JSON summary and exits non-zero on any missing or mismatched
distribution. ``--site`` restricts the lookup to one directory (for tests).
"""
import argparse
import json
import re
import sys

try:
    from importlib import metadata
except ImportError:  # pragma: no cover (Python < 3.8)
    import importlib_metadata as metadata  # type: ignore


def _version_class():
    try:
        from packaging.version import Version  # type: ignore
        return Version
    except ImportError:
        pass
    try:
        from pip._vendor.packaging.version import Version  # type: ignore
        return Version
    except ImportError:
        return None


_VERSION = _version_class()


def normalize_version(v):
    """PEP 440 normalized form; falls back to a conservative textual form."""
    v = v.strip()
    if _VERSION is not None:
        try:
            return str(_VERSION(v))
        except Exception:  # invalid version: compare textually
            pass
    return v.lower()


def normalize_name(n):
    return re.sub(r"[-_.]+", "-", n).lower()


def installed_versions(site):
    dists = metadata.distributions(path=[site]) if site else metadata.distributions()
    found = {}
    for d in dists:
        name = d.metadata.get("Name")
        if name:
            found.setdefault(normalize_name(name), d.version)
    return found


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", required=True)
    p.add_argument("--stage", choices=["core", "sci"], required=True)
    p.add_argument("--site")
    args = p.parse_args(argv)

    with open(args.manifest) as fh:
        manifest = json.load(fh)
    wanted_locks = {"bootstrap", args.stage}
    expected = {}
    for w in manifest["wheels"]:
        if wanted_locks & set(w["locks"]):
            expected[normalize_name(w["name"])] = w["version"]

    have = installed_versions(args.site)
    problems = {}
    for name, want in sorted(expected.items()):
        got = have.get(name)
        if got is None:
            problems[name] = {"want": want, "have": None}
        elif normalize_version(got) != normalize_version(want):
            problems[name] = {"want": want, "have": got}

    result = {
        "result": "pass" if expected and not problems else "fail",
        "stage": args.stage,
        "checked": len(expected),
        "torch": have.get("torch"),
        "problems": problems,
        "normalizer": "packaging" if _VERSION is not None else "textual",
    }
    print(json.dumps(result, sort_keys=True))
    return 0 if result["result"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
