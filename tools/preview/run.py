#!/usr/bin/env python3
"""
Runs a scenario against the bundled library inside the Roblox API mock (luau CLI, -O0).

  python3 tools/preview/run.py tools/preview/scenario.luau [--luau /path/to/luau]

Dumps (@@DUMP name WxH@@json) are written to tools/preview/out/<name>.json,
warnings and errors are printed. Exit code 1 on runtime errors / warnings.
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

def longstring(s):
    level = 1
    while ("]" + "=" * level + "]") in s:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{s}]{eq}]"

def main():
    scenario = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else os.path.join(HERE, "scenario.luau")
    luau = os.environ.get("LUAU", "luau")
    if "--luau" in sys.argv:
        luau = sys.argv[sys.argv.index("--luau") + 1]
    mock = open(os.path.join(HERE, "mock.luau"), encoding="utf-8").read()
    bundle = open(os.path.join(ROOT, "dist", "NovaUI.lua"), encoding="utf-8").read()
    example = open(os.path.join(ROOT, "example.lua"), encoding="utf-8").read()
    scen = open(scenario, encoding="utf-8").read()
    script = "\n".join([
        mock,
        "MOCK.BundleSource = " + longstring(bundle),
        "MOCK.ExampleSource = " + longstring(example),
        # compile bundle + example inside this -O0 chunk so the mock's typeof override applies
        "MOCK.LoadBundle = function(...)\n" + bundle + "\nend",
        "MOCK.RunExample = function(...)\n" + example + "\nend",
        """local __realLoadstring = loadstring
function loadstring(src, name)
	if src == MOCK.BundleSource then return MOCK.LoadBundle end
	if src == MOCK.ExampleSource then return MOCK.RunExample end
	return __realLoadstring(src, name)
end""",
        "Methods.HttpGet = function(_, url) return MOCK.BundleSource end",
        scen,
        "MOCK.FlushWarnings()",
    ])
    tmp = os.path.join(HERE, "out", "_run.luau")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    open(tmp, "w", encoding="utf-8").write(script)
    p = subprocess.run([luau, "-O0", tmp], capture_output=True, text=True)
    out_dir = os.path.join(HERE, "out")
    warnings, dumps, other = [], 0, []
    for line in p.stdout.splitlines():
        m = re.match(r"@@DUMP (\S+) (\d+)x(\d+)@@(.*)", line)
        if m:
            name, w, h, js = m.groups()
            with open(os.path.join(out_dir, f"{name}.json"), "w", encoding="utf-8") as f:
                f.write('{"viewport":[%s,%s],"root":%s}' % (w, h, js))
            dumps += 1
        elif line.startswith("@@WARN@@"):
            warnings.append(line[8:])
        else:
            other.append(line)
    for l in other:
        print("  |", l)
    for w in warnings:
        print("WARN:", w)
    if p.stderr.strip():
        print("STDERR:", p.stderr.strip()[:4000])
    print(f"dumps: {dumps}, warnings: {len(warnings)}, exit: {p.returncode}")
    sys.exit(1 if (p.returncode != 0 or warnings) else 0)

if __name__ == "__main__":
    main()
