"""Create a source-guarded instrumented Ipopt copy; never run an optimizer.

The installed package is read only. The generated copy adds an off-by-default
recorder around IpoptSolve, leaving the numerical statements unchanged. Execution
requires a separately prepared environment/freeze and explicit timing permission.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import stat

WRAPPER = Path("ext/IpoptMathOptInterfaceExt/MOI_wrapper.jl")
TESTED_WRAPPER_SHA256 = "18b0ea4557a3866fefad3fa78b8f09bc79528476512cf8c7d4956f70eb369f9f"
INCLUDE = 'include("utils.jl")\n'
ENTRY = 'function MOI.optimize!(model::Optimizer)\n    start_time = time()\n'
CALL = '    Ipopt.IpoptSolve(inner)\n'
INSTRUMENTED_INCLUDE = INCLUDE + '\ninclude("ivr_native_timer.jl")\nconst _formulationlab_native_recorder = IVRNativeTimer.Recorder()\n'
INSTRUMENTED_ENTRY = 'function MOI.optimize!(model::Optimizer)\n    IVRNativeTimer.reset!(_formulationlab_native_recorder, model)\n    start_time = time()\n'
INSTRUMENTED_CALL = '    IVRNativeTimer.capture!(_formulationlab_native_recorder, model) do\n        Ipopt.IpoptSolve(inner)\n    end\n'

def digest(data):
    return hashlib.sha256(data).hexdigest()

def instrument(data):
    if digest(data) != TESTED_WRAPPER_SHA256:
        raise ValueError("unsupported Ipopt wrapper bytes; review the new source before instrumentation")
    source = data.decode("utf-8")
    replacements = [(INCLUDE, INSTRUMENTED_INCLUDE), (ENTRY, INSTRUMENTED_ENTRY), (CALL, INSTRUMENTED_CALL)]
    for old, new in replacements:
        if source.count(old) != 1:
            raise ValueError("expected exactly one instrumentation anchor")
        source = source.replace(old, new)
    restored = source
    for old, new in reversed(replacements):
        restored = restored.replace(new, old)
    if restored.encode("utf-8") != data:
        raise ValueError("instrumentation did not preserve the original source")
    return source.encode("utf-8")

def source_inventory(root):
    # Include extensions and metadata, not just src/. Preserve every copied file.
    return {str(p.relative_to(root)): digest(p.read_bytes())
            for p in sorted(root.rglob("*")) if p.is_file()}

def prepare(source, output, helper=None):
    source = Path(source).resolve()
    output = Path(output).resolve()
    helper = Path(helper or Path(__file__).with_name("ivr_native_timer.jl")).resolve()
    if output.exists() or output == source or source in output.parents:
        raise ValueError("a new output directory outside the installed package is required")
    original = source_inventory(source)
    patched = instrument((source / WRAPPER).read_bytes())
    helper_bytes = helper.read_bytes()
    destination_helper = WRAPPER.parent / "ivr_native_timer.jl"
    if str(destination_helper) in original:
        raise ValueError("package already contains a timer helper")
    shutil.copytree(source, output)
    # Julia's package cache commonly marks source files read-only. Change only
    # the new copy's permissions; never chmod or edit the installed package.
    for path in (output, output / WRAPPER.parent, output / WRAPPER):
        path.chmod(path.stat().st_mode | stat.S_IWUSR)
    (output / WRAPPER).write_bytes(patched)
    (output / destination_helper).write_bytes(helper_bytes)
    copied = source_inventory(output)
    expected = dict(original)
    expected[str(WRAPPER)] = digest(patched)
    expected[str(destination_helper)] = digest(helper_bytes)
    if copied != expected or source_inventory(source) != original:
        raise ValueError("unexpected package/source change")
    manifest = dict(schema="FormulationLab.native_timer_copy.v1", source=str(source), output=str(output),
                    original_file_sha256=original, instrumented_file_sha256=copied,
                    helper_source=str(helper), helper_sha256=digest(helper_bytes),
                    wrapper_sha256=TESTED_WRAPPER_SHA256, recording_default="disabled",
                    native_boundary="IVRNativeTimer.capture! around Ipopt.IpoptSolve(inner)",
                    wrapper_metric="Original MOI.SolveTimeSec retained; includes wrapper setup and recorder bookkeeping",
                    numerical_source_restoration_verified=True, optimizer_invoked=False,
                    timing_authorized=False, execution_ready=False)
    (output / "FORMULATIONLAB_INSTRUMENTATION.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = prepare(args.source, args.output)
    print(json.dumps({k: result[k] for k in ("output", "recording_default", "optimizer_invoked", "timing_authorized")}))
