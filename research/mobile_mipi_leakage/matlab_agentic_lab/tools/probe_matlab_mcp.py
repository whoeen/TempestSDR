"""Small JSON-RPC client for verifying the official local MATLAB MCP server.
Python is used only as the transport; research calculations execute in MATLAB.
Connects to an explicitly shared existing MATLAB for execution.
"""
import argparse
import json
import pathlib
import queue
import subprocess
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--server", required=True)
    p.add_argument("--code-file")
    p.add_argument("--session-mode", choices=["auto", "existing"], default="existing")
    p.add_argument("--timeout", type=float, default=600)
    p.add_argument("--output", default=str(ROOT / "environment" / "mcp_probe.json"))
    args = p.parse_args()
    socket_dir = pathlib.Path.home() / "Documents" / "Codex" / "mcp-log"
    socket_dir.mkdir(parents=True, exist_ok=True)
    cmd = [args.server, "--matlab-session-mode=" + args.session_mode,
           "--disable-telemetry=true", "--log-folder=" + str(socket_dir)]
    if args.session_mode == "auto":
        cmd.append("--matlab-root=C:\\Program Files\\MATLAB\\R2026b")
    logs = ROOT / "environment"
    logs.mkdir(parents=True, exist_ok=True)
    with (logs / "mcp_stderr.log").open("a", encoding="utf-8") as err:
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=err, text=True, encoding="utf-8", bufsize=1)
        incoming = queue.Queue()
        def reader():
            for line in proc.stdout:
                try: incoming.put(json.loads(line))
                except json.JSONDecodeError: incoming.put({"transport_output": line})
            incoming.put({"transport_closed": True})
        threading.Thread(target=reader, daemon=True).start()
        def send(item):
            proc.stdin.write(json.dumps(item) + "\n")
            proc.stdin.flush()
        def request(ident, method, params):
            send({"jsonrpc":"2.0", "id":ident, "method":method, "params":params})
            deadline = time.monotonic() + args.timeout
            while time.monotonic() < deadline:
                obj = incoming.get(timeout=max(0.01, deadline-time.monotonic()))
                if obj.get("id") == ident and ("result" in obj or "error" in obj):
                    if "error" in obj: raise RuntimeError(obj["error"])
                    return obj["result"]
                if obj.get("method") == "roots/list":
                    send({"jsonrpc":"2.0","id":obj["id"],"result":{"roots":[
                        {"uri":ROOT.as_uri(),"name":"MATLAB smartphone laboratory"}]}})
                elif obj.get("method") == "ping":
                    send({"jsonrpc":"2.0","id":obj["id"],"result":{}})
                elif "method" in obj and "id" in obj:
                    send({"jsonrpc":"2.0","id":obj["id"],"error":{
                        "code":-32601,"message":"Client method unsupported"}})
                elif obj.get("transport_closed"):
                    raise RuntimeError("MCP process closed before response")
            raise TimeoutError(method)
        report = {"created_utc":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime())}
        try:
            report["initialize"] = request(1,"initialize",{
                "protocolVersion":"2024-11-05","capabilities":{"roots":{"listChanged":False}},
                "clientInfo":{"name":"smartphone-lab-verifier","version":"1.0"}})
            send({"jsonrpc":"2.0","method":"notifications/initialized"})
            report["tools"] = request(2,"tools/list",{})
            if args.code_file:
                code = pathlib.Path(args.code_file).read_text(encoding="utf-8-sig")
                report["execution"] = request(3,"tools/call",{
                    "name":"evaluate_matlab_code",
                    "arguments":{"code":code,"project_path":str(ROOT)}})
            pathlib.Path(args.output).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
            print(json.dumps({"server":report["initialize"].get("serverInfo"),
                              "tools":[t["name"] for t in report["tools"].get("tools",[])],
                              "execution":report.get("execution"),"output":args.output},ensure_ascii=False))
        finally:
            proc.stdin.close()
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.terminate()
                proc.wait(timeout=5)

if __name__ == "__main__":
    main()
