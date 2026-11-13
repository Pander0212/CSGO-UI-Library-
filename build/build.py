#!/usr/bin/env python3
"""
Bundles every module in /src into a single loadstring-able file: dist/NovaUI.lua

  python3 build/build.py            -> dist/NovaUI.lua
  python3 build/build.py --out x.lua

Each file becomes a module function. Module names are paths relative to /src without
the extension; a folder's init.lua is addressed by the folder name ("Skins/Classic").
Inside the bundle, `require("Core/Theme")` resolves to that module (cached).
"""
import os, sys, re, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")

def module_name(path):
    rel = os.path.relpath(path, SRC).replace(os.sep, "/")
    rel = rel[:-4]  # .lua
    if rel.endswith("/init"):
        rel = rel[:-5]
    return rel

def main():
    out = os.path.join(ROOT, "dist", "NovaUI.lua")
    if "--out" in sys.argv:
        out = sys.argv[sys.argv.index("--out") + 1]
    meta = open(os.path.join(SRC, "Meta.lua"), encoding="utf-8").read()
    name = re.search(r'Name\s*=\s*"([^"]+)"', meta).group(1)
    version = re.search(r'Version\s*=\s*"([^"]+)"', meta).group(1)
    files = []
    for d, _, fs in os.walk(SRC):
        for f in sorted(fs):
            if f.endswith(".lua"):
                files.append(os.path.join(d, f))
    files.sort()
    parts = []
    parts.append(f"-- {name} v{version} (bundled build – do not edit, edit /src and run build/build.py)\n")
    parts.append("-- built " + datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC") + "\n")
    parts.append("""local __MODULES, __CACHE, __LOADING = {}, {}, {}
local function __require(name)
	local cached = __CACHE[name]
	if cached ~= nil then
		return cached
	end
	local fn = __MODULES[name]
	if not fn then
		error("[bundle] module not found: " .. tostring(name), 2)
	end
	if __LOADING[name] then
		error("[bundle] circular require: " .. tostring(name), 2)
	end
	__LOADING[name] = true
	local result = fn(__require)
	__LOADING[name] = nil
	if result == nil then
		result = true
	end
	__CACHE[name] = result
	return result
end
""")
    for path in files:
        mod = module_name(path)
        src = open(path, encoding="utf-8").read().rstrip() + "\n"
        parts.append(f'__MODULES["{mod}"] = function(require)\n{src}end\n')
    parts.append('return __require("init")\n')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(parts))
    print(f"bundled {len(files)} modules -> {os.path.relpath(out, ROOT)} ({os.path.getsize(out)//1024} KB)")

if __name__ == "__main__":
    main()
