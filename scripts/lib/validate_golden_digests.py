"""Strict validator for tests/python/golden/p1_digests.json (SEC-08).

Called by scripts/check_repo_policy.sh as ``python3 -I <this> <file>``.
Exit 0: valid. Exit 1: invalid; one safe reason on stdout (never file
content). Any other exit: internal error, which the policy treats as fatal.

Expected structure (top level is an object, keys exactly as below):
  "synthetic":      true          (required; JSON boolean true only)
  "digests":        {name: sha256} (required; name [A-Za-z0-9._/-]{1,128},
                                    value 64 lowercase hex characters)
  "schema_version": integer >= 1  (optional)
  "generator":      string        (optional; printable ASCII, <= 200 chars)
Rejected: malformed JSON, non-UTF-8, duplicate keys at any level, NaN or
Infinity, any other key, and any "synthetic" key other than the top-level one.

The marker is a declaration, not proof of synthetic provenance: P1 must
regenerate every digest independently from its synthetic generator.
"""
import json
import re
import sys

NAME = re.compile(r"[A-Za-z0-9._/-]{1,128}\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
ALLOWED = {"synthetic", "digests", "schema_version", "generator"}


class Invalid(Exception):
    pass


def no_duplicates(pairs):
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise Invalid("duplicate key")
        seen[key] = value
    return seen


def reject_constant(_name):
    raise Invalid("NaN or Infinity is not allowed")


def count_synthetic(node):
    if isinstance(node, dict):
        return sum((k == "synthetic") + count_synthetic(v) for k, v in node.items())
    if isinstance(node, list):
        return sum(count_synthetic(v) for v in node)
    return 0


def validate(raw):
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise Invalid("not UTF-8")
    try:
        doc = json.loads(text, object_pairs_hook=no_duplicates, parse_constant=reject_constant)
    except ValueError:
        raise Invalid("malformed JSON")
    if not isinstance(doc, dict):
        raise Invalid("top level is not an object")
    extra = set(doc) - ALLOWED
    if extra:
        raise Invalid("unexpected top-level key")
    if doc.get("synthetic") is not True:
        raise Invalid('top-level "synthetic" must be the boolean true')
    if count_synthetic(doc) != 1:
        raise Invalid('"synthetic" declared more than once or nested')
    digests = doc.get("digests")
    if not isinstance(digests, dict):
        raise Invalid('"digests" must be an object')
    for name, value in digests.items():
        if not NAME.match(name):
            raise Invalid("digest name has unexpected characters or length")
        if not isinstance(value, str) or not SHA256.match(value):
            raise Invalid("digest value is not 64 lowercase hex characters")
    if "schema_version" in doc:
        v = doc["schema_version"]
        if isinstance(v, bool) or not isinstance(v, int) or v < 1:
            raise Invalid('"schema_version" must be an integer >= 1')
    if "generator" in doc:
        g = doc["generator"]
        if not isinstance(g, str) or len(g) > 200 or not all(" " <= c <= "~" for c in g):
            raise Invalid('"generator" must be printable ASCII, at most 200 characters')


def main():
    if len(sys.argv) != 2:
        print("usage: validate_golden_digests.py FILE")
        return 2
    with open(sys.argv[1], "rb") as handle:
        raw = handle.read()
    try:
        validate(raw)
    except Invalid as exc:
        print(exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
