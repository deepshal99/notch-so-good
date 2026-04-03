#!/bin/bash
# Installs Codex CLI hooks for Notch So Good
# Communicates via Unix domain socket at /tmp/notchsogood.sock
# Only dependency: python3 (pre-installed on macOS)

set -e

CODEX_DIR="$HOME/.codex"
CONFIG_FILE="$CODEX_DIR/config.toml"
HOOKS_FILE="$CODEX_DIR/hooks.json"
SOCKET_PATH="/tmp/notchsogood.sock"

# Create directory if needed
mkdir -p "$CODEX_DIR"

# Enable hooks feature flag in config.toml
if [ -f "$CONFIG_FILE" ]; then
    if grep -q 'codex_hooks' "$CONFIG_FILE"; then
        # Update existing flag
        sed -i '' 's/codex_hooks.*/codex_hooks = true/' "$CONFIG_FILE"
    elif grep -q '\[features\]' "$CONFIG_FILE"; then
        # Add under existing [features] section
        sed -i '' '/\[features\]/a\
codex_hooks = true
' "$CONFIG_FILE"
    else
        # Add new [features] section
        printf '\n[features]\ncodex_hooks = true\n' >> "$CONFIG_FILE"
    fi
else
    cat > "$CONFIG_FILE" << 'EOF'
[features]
codex_hooks = true
EOF
fi

if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required (should be pre-installed on macOS)."
    exit 1
fi

# Backup existing hooks file
if [ -f "$HOOKS_FILE" ]; then
    cp "$HOOKS_FILE" "$HOOKS_FILE.backup.$(date +%s)"
fi

# Write hooks.json with all supported events
# All hooks communicate via Unix socket at /tmp/notchsogood.sock
cat > "$HOOKS_FILE" << 'HOOKSEOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"\nimport sys, json, socket, os\ntry:\n    d = json.load(sys.stdin)\n    msg = json.dumps({\n        'event': 'SessionStart',\n        'session_id': d.get('session_id', ''),\n        'cwd': d.get('cwd', ''),\n        'source_app': 'codex',\n        'model': d.get('model', '')\n    })\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"\nimport sys, json, socket\ntry:\n    d = json.load(sys.stdin)\n    msg = json.dumps({\n        'event': 'Stop',\n        'session_id': d.get('session_id', ''),\n        'last_assistant_message': d.get('last_assistant_message', 'Task completed')[:200]\n    })\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"",
            "timeout": 5
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"\nimport sys, json, socket\ntry:\n    d = json.load(sys.stdin)\n    msg = json.dumps({\n        'event': 'UserPromptSubmit',\n        'session_id': d.get('session_id', '')\n    })\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"\nimport sys, json, socket\ntry:\n    d = json.load(sys.stdin)\n    msg = json.dumps({\n        'event': 'PostToolUse',\n        'session_id': d.get('session_id', ''),\n        'tool_name': d.get('tool_name', '')\n    })\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"\nimport sys, json, socket\n\ntry:\n    d = json.load(sys.stdin)\nexcept:\n    sys.exit(0)\n\ntn = d.get('tool_name', '')\nti = d.get('tool_input', {})\nsid = d.get('session_id', '')\n\n# Extract human-readable summary from tool_input (which is an object in Codex)\nif isinstance(ti, dict):\n    if tn == 'Bash':\n        summary = ti.get('command', json.dumps(ti))[:200]\n    elif tn in ('Edit', 'Write', 'Read'):\n        summary = ti.get('file_path', json.dumps(ti))[:200]\n    else:\n        summary = json.dumps(ti)[:200]\nelse:\n    summary = str(ti)[:200]\n\n# Send to NotchSoGood socket (bidirectional — wait for response)\ntry:\n    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    sock.settimeout(120)\n    sock.connect('/tmp/notchsogood.sock')\n    msg = json.dumps({\n        'event': 'PreToolUse',\n        'tool_name': tn,\n        'tool_input': summary,\n        'session_id': sid,\n        'source_app': 'codex'\n    })\n    sock.sendall(msg.encode())\n    sock.shutdown(socket.SHUT_WR)\n    resp = b''\n    while True:\n        chunk = sock.recv(4096)\n        if not chunk:\n            break\n        resp += chunk\n    sock.close()\n    if resp:\n        r = json.loads(resp.decode())\n        if r.get('decision') == 'deny':\n            reason = r.get('reason', 'Denied from Notch So Good')\n            sys.stderr.write(reason)\n            sys.exit(2)\n        else:\n            print(json.dumps({'permissionDecision': 'allow'}))\nexcept SystemExit:\n    raise\nexcept:\n    pass\n\"",
            "timeout": 300
          }
        ]
      }
    ]
  }
}
HOOKSEOF

echo "Codex CLI hooks installed!"
echo "  Config:  $CONFIG_FILE (codex_hooks = true)"
echo "  Hooks:   $HOOKS_FILE"
echo "  Events:  SessionStart, Stop, UserPromptSubmit, PreToolUse, PostToolUse"
echo "  Socket:  $SOCKET_PATH"
echo ""
echo "  Make sure Notch So Good is running to receive notifications."
