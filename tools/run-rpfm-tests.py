"""Run RPFM's Lua 5.1 test harness against a local pack.

Required: RPFM 5.1.1, WH3, a matching schema and Assembly Kit scripting docs.
Defaults read RPFM_SERVER, WH3_SCHEMA and WH3_DATA (the game's data directory).
All generated evidence is stored under .local/rpfm, never in the game directory.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".local/rpfm"
URL = "http://127.0.0.1:45127"


def save(name, data):
    (OUT / name).write_text(
        json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def start_server(exe, schema, game, docs):
    try:
        version = json.load(urllib.request.urlopen(URL + "/version", timeout=2))
        marker = json.loads((OUT / "server.json").read_text())
        if version["version"] != "5.1.1" or marker["pid"] != version["pid"]:
            raise RuntimeError("Port belongs to another RPFM instance")
        return version
    except (urllib.error.URLError, TimeoutError):
        pass
    profile = OUT / "profile"
    config = profile / "FrodoWazEre/rpfm/config"
    config.mkdir(parents=True, exist_ok=True)
    settings = config / "settings.json"
    if not settings.exists():
        settings.write_text(
            json.dumps({
                "bool": {
                    "enable_usage_telemetry": False,
                    "enable_crash_reports": False,
                },
                "string": {
                    "default_game": "warhammer_3",
                    "warhammer_3": str(game),
                    "warhammer_3_assembly_kit": str(docs),
                },
                "i32": {},
                "f32": {},
                "raw_data": {},
                "vec_string": {},
            }),
            encoding="utf-8",
        )
    (config / "schemas").mkdir(exist_ok=True)
    shutil.copy2(schema, config / "schemas/schema_wh3.ron")
    env = os.environ.copy()
    env["APPDATA"] = str(profile)
    with (OUT / "server.log").open("ab") as log:
        process = subprocess.Popen(
            [str(exe)],
            cwd=exe.parent,
            env=env,
            stdout=log,
            stderr=log,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
    save("server.json", {
        "pid": process.pid,
        "exe": str(exe),
        "profile": str(profile),
    })
    for _ in range(60):
        try:
            return json.load(urllib.request.urlopen(URL + "/version", timeout=2))
        except (urllib.error.URLError, TimeoutError):
            time.sleep(.5)
    raise RuntimeError("RPFM startup failed; see .local/rpfm/server.log")


class MCP:
    def __init__(self):
        self.session = None
        self.ident = 0
        self.rpc("initialize", {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "clientInfo": {"name": "everchosen-tests", "version": "1"},
        })
        self.rpc("notifications/initialized", {}, True)

    def rpc(self, method, params, notify=False):
        self.ident += 1
        body = {"jsonrpc": "2.0", "method": method, "params": params}
        if not notify:
            body["id"] = self.ident
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "MCP-Protocol-Version": "2025-03-26",
        }
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        request = urllib.request.Request(
            URL + "/mcp", json.dumps(body).encode(), headers
        )
        with urllib.request.urlopen(request, timeout=900) as response:
            self.session = response.headers.get("Mcp-Session-Id", self.session)
            if notify:
                return
            if "text/event-stream" in response.headers.get("Content-Type", ""):
                for line in response:
                    if line.startswith(b"data:") and line[5:].strip():
                        result = json.loads(line[5:])
                        if result.get("id") == self.ident:
                            break
                else:
                    raise RuntimeError("No MCP response")
            else:
                result = json.load(response)
        if "error" in result:
            raise RuntimeError(str(result["error"]))
        return result["result"]

    def tool(self, name, **args):
        print("RPFM " + name, flush=True)
        response = self.rpc("tools/call", {"name": name, "arguments": args})
        if response.get("isError"):
            raise RuntimeError(str(response))
        values = []
        for item in response.get("content", []):
            if item["type"] == "text":
                try:
                    values.append(json.loads(item["text"]))
                except ValueError:
                    values.append(item["text"])
        result = values[0] if len(values) == 1 else values
        if isinstance(result, dict) and "Error" in result:
            raise RuntimeError(str(result))
        return result


def test_source(path, distribution):
    path = path.resolve()
    if path.suffix == ".lua":
        return path.read_text(encoding="utf-8-sig")
    if path.suffix != ".fnl":
        raise ValueError("Test source must be .lua or .fnl: " + str(path))

    def wsl_path(value):
        return subprocess.run(
            ["wsl.exe", "-d", distribution, "--exec", "wslpath", "-a",
             str(value).replace("\\", "/")],
            check=True,
            capture_output=True,
        ).stdout.decode("utf-8").strip()

    activate = wsl_path(ROOT / "tools/wsl/activate.sh")
    source = wsl_path(path)
    # Arguments are passed separately; paths are never interpolated into shell code.
    compiled = subprocess.run(
        ["wsl.exe", "-d", distribution, "--exec", "bash", "-c",
         'set -e; source "$1"; fennel --globals rpfm,GAME,cm,core --correlate --compile "$2"',
         "compile-test", activate, source],
        cwd=ROOT,
        check=True,
        capture_output=True,
    ).stdout.decode("utf-8")
    subprocess.run(
        ["wsl.exe", "-d", distribution, "--exec", "luac5.1", "-p", "-"],
        input=compiled.encode("utf-8"),
        check=True,
        capture_output=True,
    )
    generated = OUT / "compiled"
    generated.mkdir(parents=True, exist_ok=True)
    (generated / (path.stem + ".lua")).write_text(
        compiled, encoding="utf-8", newline="\n"
    )
    return compiled


def main():
    game_data = os.environ.get("WH3_DATA")
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--server", type=Path, default=os.environ.get("RPFM_SERVER") or None,
        help="RPFM server executable; defaults to RPFM_SERVER",
    )
    parser.add_argument(
        "--schema", type=Path, default=os.environ.get("WH3_SCHEMA") or None,
        help="WH3 schema; defaults to WH3_SCHEMA",
    )
    parser.add_argument(
        "--game", type=Path, default=Path(game_data).parent if game_data else None,
        help="WH3 game root; defaults to the parent of WH3_DATA",
    )
    parser.add_argument(
        "--docs", type=Path,
        help="Official Assembly Kit root; defaults to <game>/assembly_kit",
    )
    parser.add_argument(
        "--pack", type=Path,
        default=ROOT / "dist/everchosen_tamurkhan_chieftains.pack",
    )
    parser.add_argument("--test", type=Path, required=True)
    parser.add_argument("--output", default="report.json")
    parser.add_argument("--generate-cache", action="store_true")
    parser.add_argument("--campaign")
    parser.add_argument(
        "--distribution", default="Ubuntu",
        help="WSL distribution for Fennel compilation",
    )
    args = parser.parse_args()
    missing = [
        f"--{option} or {variable}"
        for option, variable in (
            ("server", "RPFM_SERVER"),
            ("schema", "WH3_SCHEMA"),
            ("game", "WH3_DATA (the game's data directory)"),
        )
        if getattr(args, option) is None
    ]
    if missing:
        parser.error("Required paths missing: set " + "; ".join(missing))
    args.docs = (args.docs or args.game / "assembly_kit").resolve()
    api_doc = args.docs / "documentation/script/script/scripting_doc.html"
    if not api_doc.is_file():
        parser.error("Assembly Kit scripting documentation not found: " + str(api_doc))
    OUT.mkdir(parents=True, exist_ok=True)
    source = test_source(args.test, args.distribution)
    version = start_server(args.server, args.schema, args.game, args.docs)
    print(version, flush=True)
    client = MCP()
    save("tool-catalog.json", client.rpc("tools/list", {}))
    save("actual-config-path.json", client.tool("config_path"))
    previous_docs = client.tool(
        "settings_get_path_buf", value="warhammer_3_assembly_kit"
    )
    save("previous-docs-setting.json", previous_docs)
    try:
        client.tool(
            "settings_set_path_buf", key="warhammer_3_assembly_kit",
            value=str(args.docs.resolve()),
        )
        save("setup.json", client.tool(
            "set_game_selected", game_name="warhammer_3", rebuild_dependencies=True
        ))
        if args.generate_cache:
            save("cache.json", client.tool("generate_dependencies_cache"))
            client.tool("rebuild_dependencies", value=True)
        save("open.json", client.tool(
            "open_packfiles", paths=[str(args.pack.resolve())]
        ))
        params = {"test_source": source}
        if args.campaign:
            params["campaign"] = args.campaign
        result = client.tool("lua_run_tests", **params)
        save(args.output, {
            "server": version,
            "assembly_kit": str(args.docs),
            "api_doc_sha256": hashlib.sha256(api_doc.read_bytes()).hexdigest(),
            "pack_sha256": hashlib.sha256(args.pack.read_bytes()).hexdigest(),
            "test_source": str(args.test.resolve()),
            "test_sha256": hashlib.sha256(args.test.read_bytes()).hexdigest(),
            "executed_lua_sha256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
            "result": result,
        })
        report = result.get("LuaTestReport", {})
        print(json.dumps({
            "tests": [
                {key: test.get(key) for key in
                 ("name", "passed", "errors", "unmocked_calls")}
                for test in report.get("tests", [])
            ],
            "boot_errors": report.get("boot_errors", []),
        }, ensure_ascii=True), flush=True)
    finally:
        old_path = (
            next(iter(previous_docs.values()))
            if isinstance(previous_docs, dict) else previous_docs
        )
        client.tool(
            "settings_set_path_buf", key="warhammer_3_assembly_kit", value=old_path
        )
    tests = report.get("tests", [])
    return 0 if tests and not report.get("boot_errors") and all(
        test.get("passed") and not test.get("errors") and not test.get("unmocked_calls")
        for test in tests
    ) else 1


if __name__ == "__main__":
    raise SystemExit(main())
