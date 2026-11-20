import json
import os
import selectors
import subprocess
import time

sha = subprocess.check_output(
    ["git", "rev-parse", "--short", "HEAD"], text=True
).strip()
image = os.environ.get("QA_IMAGE", "redcarlos/qa-agents:" + sha)
name = "qa-mcp-smoke-" + str(os.getpid())

process = subprocess.Popen(
    [
        "docker", "run", "--rm", "-i", "--init",
        "--name", name,
        "--cpus", "1", "--memory", "1g",
        "--memory-swap", "1g", "--shm-size", "256m",
        "--network", "none",
        "--entrypoint", "playwright-mcp", image,
        "--headless", "--no-sandbox",
        "--executable-path", "/usr/local/bin/qa-chromium",
    ],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True,
    bufsize=1,
)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)

def send(message):
    process.stdin.write(json.dumps(message) + "\n")
    process.stdin.flush()

def request(number, method, params):
    send({"jsonrpc": "2.0", "id": number,
          "method": method, "params": params})
    deadline = time.monotonic() + 60
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not selector.select(remaining):
            raise RuntimeError("MCP response timeout")
        line = process.stdout.readline()
        if not line:
            raise RuntimeError("MCP process exited")
        message = json.loads(line)
        if message.get("id") != number:
            continue
        if "error" in message:
            raise RuntimeError(str(message["error"])[:1500])
        result = message["result"]
        if result.get("isError"):
            raise RuntimeError(str(result)[:1500])
        return result

try:
    request(1, "initialize", {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "qa-smoke", "version": "1.0"},
    })
    send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    tools = request(2, "tools/list", {})
    names = {tool["name"] for tool in tools["tools"]}
    if not {"browser_navigate", "browser_snapshot"} <= names:
        raise RuntimeError("Required MCP tools missing")
    print("MCP tools: OK", flush=True)
    request(3, "tools/call", {
        "name": "browser_navigate",
        "arguments": {"url": "about:blank"},
    })
    request(4, "tools/call", {
        "name": "browser_snapshot", "arguments": {},
    })
    print("MCP browser navigation and snapshot: OK", flush=True)
finally:
    selector.close()
    subprocess.run(
        ["docker", "rm", "-f", name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    process.communicate(timeout=15)
