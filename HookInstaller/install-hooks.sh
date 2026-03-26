#!/bin/bash
# Installs Claude Code hooks for Notch So Good
# Communicates via Unix domain socket at /tmp/notchsogood.sock
# Only dependency: python3 (pre-installed on macOS)

set -e

SETTINGS_FILE="$HOME/.claude/settings.json"
SOCKET_PATH="/tmp/notchsogood.sock"

# Create directory if needed
mkdir -p "$HOME/.claude"

# Create settings file if it doesn't exist
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required (should be pre-installed on macOS)."
    exit 1
fi

# Validate existing settings file is valid JSON
if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS_FILE" 2>/dev/null; then
    echo "Error: $SETTINGS_FILE is not valid JSON. Please fix it manually."
    exit 1
fi

# Backup existing settings
cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%s)"

# === HOOK DEFINITIONS ===
# All hooks communicate via Unix socket at /tmp/notchsogood.sock
# Fire-and-forget hooks: SessionStart, Stop, Notification, PostToolUse, SessionEnd, UserPromptSubmit, PreCompact, SubagentStop
# Bidirectional hooks: PreToolUse (waits for approve/deny response)

# --- SessionStart: session began ---
read -r -d '' SESSIONSTART_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); echo \"$INPUT\" | python3 -c \"\nimport sys, json, socket, os\nd = json.load(sys.stdin)\nmsg = json.dumps({'event':'SessionStart','session_id':d.get('session_id',''),'cwd':d.get('cwd',''),'source_app':os.environ.get('__CFBundleIdentifier',os.environ.get('TERM_PROGRAM_BUNDLE_ID',''))})\ntry:\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"","timeout":5000}]}]
HOOKEOF

# --- SessionEnd: session ended ---
read -r -d '' SESSIONEND_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); echo \"$INPUT\" | python3 -c \"\nimport sys, json, socket\nd = json.load(sys.stdin)\nmsg = json.dumps({'event':'SessionEnd','session_id':d.get('session_id','')})\ntry:\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"","timeout":5000}]}]
HOOKEOF

# --- Stop: task completed ---
read -r -d '' STOP_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); echo \"$INPUT\" | python3 -c \"\nimport sys, json, socket\nd = json.load(sys.stdin)\nmsg = json.dumps({'event':'Stop','session_id':d.get('session_id',''),'last_assistant_message':d.get('last_assistant_message','Task completed')[:200]})\ntry:\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"","timeout":5000}]}]
HOOKEOF

# --- Notification: Claude wants user attention ---
read -r -d '' NOTIFICATION_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); echo \"$INPUT\" | python3 -c \"\nimport sys, json, socket\nd = json.load(sys.stdin)\nmsg = json.dumps({'event':'Notification','session_id':d.get('session_id',''),'notification_type':d.get('notification_type','general'),'message':d.get('message','Claude needs attention')[:200],'title':d.get('title','')})\ntry:\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"","timeout":5000}]}]
HOOKEOF

# --- UserPromptSubmit: user sent a message ---
read -r -d '' USERPROMPTSUBMIT_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); echo \"$INPUT\" | python3 -c \"\nimport sys, json, socket\nd = json.load(sys.stdin)\nmsg = json.dumps({'event':'UserPromptSubmit','session_id':d.get('session_id','')})\ntry:\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"","timeout":5000}]}]
HOOKEOF

# --- PreCompact: context compaction starting ---
read -r -d '' PRECOMPACT_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); echo \"$INPUT\" | python3 -c \"\nimport sys, json, socket\nd = json.load(sys.stdin)\nmsg = json.dumps({'event':'PreCompact','session_id':d.get('session_id','')})\ntry:\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"","timeout":5000}]}]
HOOKEOF

# --- SubagentStart: subagent spawned ---
read -r -d '' SUBAGENTSTART_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); echo \"$INPUT\" | python3 -c \"\nimport sys, json, socket\nd = json.load(sys.stdin)\nmsg = json.dumps({'event':'SubagentStart','session_id':d.get('session_id',''),'subagent_id':d.get('subagent_id',d.get('task_id','')),'description':d.get('description',d.get('prompt','Agent task'))[:80]})\ntry:\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"","timeout":5000}]}]
HOOKEOF

# --- SubagentStop: subagent finished ---
read -r -d '' SUBAGENTSTOP_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); echo \"$INPUT\" | python3 -c \"\nimport sys, json, socket\nd = json.load(sys.stdin)\nmsg = json.dumps({'event':'SubagentStop','session_id':d.get('session_id',''),'subagent_id':d.get('subagent_id',d.get('task_id',''))})\ntry:\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"","timeout":5000}]}]
HOOKEOF

# --- PostToolUse: tool finished executing ---
read -r -d '' POSTTOOLUSE_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); echo \"$INPUT\" | python3 -c \"\nimport sys, json, socket\nd = json.load(sys.stdin)\nmsg = json.dumps({'event':'PostToolUse','session_id':d.get('session_id',''),'tool_name':d.get('tool_name','')})\ntry:\n    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    s.connect('/tmp/notchsogood.sock')\n    s.sendall(msg.encode())\n    s.close()\nexcept: pass\n\"","timeout":5000}]}]
HOOKEOF

# --- PreToolUse: permission check (bidirectional — waits for response) ---
# Auto-approves safe tools locally (no socket round-trip needed).
# Sends dangerous tools to the app's socket server and waits for approve/deny.
read -r -d '' PRETOOLUSE_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); echo \"$INPUT\" | python3 -c \"\nimport sys, json, socket, os, fnmatch\n\nd = json.load(sys.stdin)\ntn = d.get('tool_name', '')\nti = d.get('tool_input', {})\nsid = d.get('session_id', '')\n\n# Extract human-readable summary\nif tn == 'Bash':\n    summary = ti.get('command', '') if isinstance(ti, dict) else str(ti)[:200]\nelif tn in ('Edit', 'Write', 'Read', 'NotebookEdit'):\n    summary = ti.get('file_path', '') if isinstance(ti, dict) else str(ti)[:200]\nelif tn == 'Grep':\n    summary = ti.get('pattern', '') if isinstance(ti, dict) else str(ti)[:200]\nelse:\n    summary = json.dumps(ti)[:200] if isinstance(ti, dict) else str(ti)[:200]\n\n# --- Settings paths ---\nsettings_paths = [\n    os.path.expanduser('~/.claude/settings.json'),\n    os.path.expanduser('~/.claude/settings.local.json'),\n]\n\n# --- 1. Dangerous mode bypass ---\nfor p in settings_paths:\n    try:\n        with open(p) as f:\n            s = json.load(f)\n        if s.get('skipDangerousModePermissionPrompt') or s.get('dangerouslySkipPermissions'):\n            print(json.dumps({'decision':'approve'}))\n            sys.exit(0)\n    except: pass\n\n# --- 2. Built-in safe tools ---\nSAFE = {\n    'Read','Glob','Grep','LSP','Agent','ToolSearch',\n    'EnterPlanMode','ExitPlanMode','EnterWorktree','ExitWorktree',\n    'TaskGet','TaskList','TaskOutput','TaskCreate','TaskUpdate','TaskStop',\n    'CronList','ListMcpResourcesTool','ReadMcpResourceTool',\n    'Skill','SendMessage','WebFetch','WebSearch','NotebookEdit',\n    'mcp__conductor__AskUserQuestion','mcp__conductor__DiffComment',\n    'mcp__conductor__GetTerminalOutput','mcp__conductor__GetWorkspaceDiff',\n}\nif tn in SAFE:\n    print(json.dumps({'decision':'approve'}))\n    sys.exit(0)\n\n# --- 3. MCP read-only heuristic ---\nif tn.startswith('mcp__'):\n    parts = tn.split('__')\n    func = parts[-1].lower() if len(parts) >= 3 else ''\n    read_only = ['get_','list_','search_','read_','find_','query_','resolve','snapshot','watch','fetch']\n    if any(kw in func for kw in read_only):\n        print(json.dumps({'decision':'approve'}))\n        sys.exit(0)\n\n# --- 4. User allow rules ---\nallowed = []\nfor p in settings_paths:\n    try:\n        with open(p) as f:\n            s = json.load(f)\n        allowed.extend(s.get('permissions', {}).get('allow', []))\n    except: pass\n\nfor rule in allowed:\n    if '(' in rule:\n        rtn = rule[:rule.index('(')]\n        rpat = rule[rule.index('(')+1:rule.rindex(')')]\n        if tn != rtn: continue\n        if rpat == '*' or (rpat.endswith(':*') and summary.startswith(rpat[:-2])) or fnmatch.fnmatch(summary, rpat):\n            print(json.dumps({'decision':'approve'}))\n            sys.exit(0)\n    else:\n        if tn == rule or tn.startswith(rule + '__'):\n            print(json.dumps({'decision':'approve'}))\n            sys.exit(0)\n\n# --- 5. Send to socket server for user approval ---\ntry:\n    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n    sock.settimeout(120)\n    sock.connect('/tmp/notchsogood.sock')\n    msg = json.dumps({'event':'PreToolUse','tool_name':tn,'tool_input':summary[:200],'session_id':sid})\n    sock.sendall(msg.encode())\n    sock.shutdown(socket.SHUT_WR)\n    resp = b''\n    while True:\n        chunk = sock.recv(4096)\n        if not chunk: break\n        resp += chunk\n    sock.close()\n    if resp:\n        print(resp.decode())\nexcept:\n    pass\n\"","timeout":300000}]}]
HOOKEOF

# Merge all hooks into settings using python3
UPDATED=$(python3 -c "
import json, sys

settings_path = sys.argv[1]
hooks_data = {}
# Parse hook arguments: name=json pairs
for i in range(2, len(sys.argv), 2):
    name = sys.argv[i]
    hook_json = json.loads(sys.argv[i+1])
    hooks_data[name] = hook_json

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
hooks.update(hooks_data)
settings['hooks'] = hooks

print(json.dumps(settings, indent=2))
" "$SETTINGS_FILE" \
    "SessionStart" "$SESSIONSTART_HOOK" \
    "SessionEnd" "$SESSIONEND_HOOK" \
    "Stop" "$STOP_HOOK" \
    "Notification" "$NOTIFICATION_HOOK" \
    "UserPromptSubmit" "$USERPROMPTSUBMIT_HOOK" \
    "PreCompact" "$PRECOMPACT_HOOK" \
    "SubagentStart" "$SUBAGENTSTART_HOOK" \
    "SubagentStop" "$SUBAGENTSTOP_HOOK" \
    "PostToolUse" "$POSTTOOLUSE_HOOK" \
    "PreToolUse" "$PRETOOLUSE_HOOK")

if [ -z "$UPDATED" ]; then
    echo "Error: Failed to update settings — restoring backup"
    LATEST_BACKUP=$(ls -t "$SETTINGS_FILE.backup."* 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then cp "$LATEST_BACKUP" "$SETTINGS_FILE"; fi
    exit 1
fi

echo "$UPDATED" > "$SETTINGS_FILE"

echo "Claude Code hooks installed!"
echo "  Settings: $SETTINGS_FILE"
echo "  Hooks: SessionStart, SessionEnd, Stop, Notification, PreToolUse, PostToolUse,"
echo "         UserPromptSubmit, PreCompact, SubagentStart, SubagentStop"
echo "  Socket: $SOCKET_PATH"
echo ""
echo "  Make sure Notch So Good is running to receive notifications."
echo "  Permission approvals work automatically when the app is running."
