"""PROPOSED - NOT APPROVED. Bounded CUDA smoke test for the Xavier research venv.

Run only by scripts/proposed/install_xavier_env.sh, through the venv's
``activate`` (the same scoped environment later research runs use). It is not
a benchmark and changes no power or clock settings.

Checks:
  * the scoped environment: VIRTUAL_ENV is this interpreter's prefix, CUDA_HOME
    is the expected toolkit, nvcc on PATH comes from it, its lib64 is on
    LD_LIBRARY_PATH, and torch/matplotlib caches live inside the venv;
  * torch: CUDA build 11.4, CUDA available, cuDNN present;
  * a 1024x1024 float32 matmul on the GPU matches the CPU result;
  * a 256 MiB GPU allocation is written, read back and released;
  * sci stage only: every pinned distribution in the sci lock is installed at
    its pinned version and the scientific modules import.

Writes a JSON result to --out (no usernames or hostnames) and exits non-zero
on any failed check.
"""
import argparse
import importlib
import json
import os
import re
import shutil
import sys
import time

SCI_MODULES = [
    "numpy", "scipy", "skimage", "nibabel", "SimpleITK", "torchio", "einops",
    "batchgenerators", "matplotlib", "sklearn", "pandas", "PIL", "tqdm",
]


def check(results, name, ok, detail=None):
    results["checks"].append({"name": name, "ok": bool(ok), "detail": detail})
    if not ok:
        raise AssertionError("%s failed: %s" % (name, detail))


def under(path, prefix):
    path, prefix = os.path.realpath(path), os.path.realpath(prefix)
    return path == prefix or path.startswith(prefix + os.sep)


def check_environment(results, cuda_home):
    venv = os.environ.get("VIRTUAL_ENV", "")
    check(results, "venv_active", venv and os.path.realpath(sys.prefix) == os.path.realpath(venv),
          {"sys_prefix_is_venv": bool(venv)})
    check(results, "cuda_home", os.environ.get("CUDA_HOME") == cuda_home, os.environ.get("CUDA_HOME"))
    nvcc = shutil.which("nvcc")
    check(results, "nvcc_from_cuda_home", nvcc is not None and under(nvcc, cuda_home), nvcc)
    ld = os.environ.get("LD_LIBRARY_PATH", "").split(":")
    check(results, "cuda_lib64_on_ld_path", os.path.join(cuda_home, "lib64") in ld, None)
    for var in ("TORCH_HOME", "MPLCONFIGDIR", "XDG_CACHE_HOME"):
        val = os.environ.get(var, "")
        check(results, "cache_in_venv:" + var, bool(val) and under(val, venv), None)


def gpu_checks(results):
    import torch  # noqa: WPS433 (imported after environment checks)

    results["torch_version"] = torch.__version__
    results["torch_cuda_build"] = torch.version.cuda
    results["cudnn_version"] = torch.backends.cudnn.version()
    check(results, "torch_cuda_build_11.4", torch.version.cuda == "11.4", torch.version.cuda)
    check(results, "cuda_available", torch.cuda.is_available(), None)
    check(results, "cudnn_available", results["cudnn_version"] is not None, results["cudnn_version"])
    results["device_name"] = torch.cuda.get_device_name(0)
    results["device_capability"] = list(torch.cuda.get_device_capability(0))

    # 1. Tensor functionality: GPU result must match CPU result.
    a = torch.arange(1024 * 1024, dtype=torch.float32).reshape(1024, 1024) / 1e6
    ref = a @ a.T
    t0 = time.monotonic()
    got = (a.cuda() @ a.cuda().T).cpu()
    torch.cuda.synchronize()
    results["matmul_seconds"] = round(time.monotonic() - t0, 4)
    max_abs = float((ref - got).abs().max())
    results["matmul_max_abs_error"] = max_abs
    check(results, "gpu_cpu_matmul_allclose", torch.allclose(ref, got, rtol=1e-3, atol=1e-2), max_abs)

    # 2. Memory allocation: 256 MiB, write, read back, release.
    torch.cuda.reset_peak_memory_stats()
    free0, total = torch.cuda.mem_get_info()
    x = torch.ones(64 * 1024 * 1024, dtype=torch.float32, device="cuda")
    torch.cuda.synchronize()
    readback = float(x.sum().item())
    peak = torch.cuda.max_memory_allocated()
    del x
    torch.cuda.empty_cache()
    free1, _ = torch.cuda.mem_get_info()
    mib = 2 ** 20
    results["memory"] = {
        "total_mib": round(total / mib, 1),
        "free_before_mib": round(free0 / mib, 1),
        "free_after_mib": round(free1 / mib, 1),
        "peak_allocated_mib": round(peak / mib, 1),
        "requested_mib": 256,
    }
    check(results, "alloc_256mib_readback", readback == float(64 * 1024 * 1024), readback)
    check(results, "alloc_peak_at_least_256mib", peak >= 256 * mib, results["memory"]["peak_allocated_mib"])


def sci_checks(results, lock_path):
    try:
        from importlib import metadata
    except ImportError:  # pragma: no cover
        import importlib_metadata as metadata  # type: ignore

    pins = {}
    with open(lock_path) as fh:
        for line in fh:
            m = re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)==([^\s\\;]+)", line)
            if m:
                pins[m.group(1).lower().replace("_", "-")] = m.group(2)
    mismatched = {}
    for dist, want in sorted(pins.items()):
        try:
            have = metadata.version(dist)
        except metadata.PackageNotFoundError:
            have = None
        if have != want:
            mismatched[dist] = {"want": want, "have": have}
    results["sci_pins_checked"] = len(pins)
    check(results, "sci_pinned_versions", not mismatched and pins, mismatched)

    os.environ.setdefault("MPLBACKEND", "Agg")
    versions = {}
    for mod in SCI_MODULES:
        m = importlib.import_module(mod)
        versions[mod] = str(getattr(m, "__version__", "n/a"))
    results["sci_imports"] = versions
    check(results, "sci_imports", len(versions) == len(SCI_MODULES), None)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--stage", choices=["core", "sci"], required=True)
    p.add_argument("--cuda-home", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--sci-lock")
    args = p.parse_args()
    results = {"stage": args.stage, "python": sys.version.split()[0], "checks": [], "result": "fail"}
    rc = 1
    try:
        check_environment(results, args.cuda_home)
        gpu_checks(results)
        if args.stage == "sci":
            if not args.sci_lock:
                raise AssertionError("--sci-lock is required for the sci stage")
            sci_checks(results, args.sci_lock)
        results["result"] = "pass"
        rc = 0
    except Exception as exc:  # report every failure in the record, then fail
        results["error"] = "%s: %s" % (type(exc).__name__, exc)
    with open(args.out, "w") as fh:
        json.dump(results, fh, sort_keys=True)
    print(json.dumps({k: results.get(k) for k in (
        "result", "torch_version", "torch_cuda_build", "cudnn_version", "device_capability", "memory", "error")},
        sort_keys=True))
    return rc


if __name__ == "__main__":
    sys.exit(main())
