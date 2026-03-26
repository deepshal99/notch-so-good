#!/bin/bash
# Installs Claude Code hooks for Notch So Good
# This script adds hooks to ~/.claude/settings.json
# Only dependency: python3 (pre-installed on macOS)

set -e

SETTINGS_FILE="$HOME/.claude/settings.json"

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

# Hooks use python3 instead of jq for JSON parsing (python3 is pre-installed on macOS, jq is not)
# Each hook command: reads JSON from stdin via python3, extracts fields, URL-encodes, calls open -g

read -r -d '' START_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); eval $(echo \"$INPUT\" | python3 -c \"import sys,json,urllib.parse; d=json.load(sys.stdin); sid=d.get('session_id',''); cwd=d.get('cwd','') or ''; print(f'SID={sid}'); print(f'ECWD={urllib.parse.quote(cwd)}')\"); SRCAPP=${__CFBundleIdentifier:-${TERM_PROGRAM_BUNDLE_ID:-}}; open -g \"notchsogood://session_start?session_id=$SID&cwd=$ECWD&source_app=$SRCAPP\"","timeout":5000}]}]
HOOKEOF

read -r -d '' NOTIFICATION_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); eval $(echo \"$INPUT\" | python3 -c \"import sys,json,urllib.parse; d=json.load(sys.stdin); t=d.get('notification_type','general'); nt={'permission_prompt':'permission','idle_prompt':'question'}.get(t,'general'); msg=urllib.parse.quote(d.get('message','Claude needs attention')[:200]); title=urllib.parse.quote(d.get('title','')); sid=d.get('session_id',''); print(f'NTYPE={nt}'); print(f'MSG={msg}'); print(f'TITLE={title}'); print(f'SID={sid}')\"); open -g \"notchsogood://notify?type=$NTYPE&message=$MSG&title=$TITLE&session_id=$SID\"","timeout":5000}]}]
HOOKEOF

read -r -d '' STOP_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); eval $(echo \"$INPUT\" | python3 -c \"import sys,json,urllib.parse; d=json.load(sys.stdin); msg=urllib.parse.quote(d.get('last_assistant_message','Task completed')[:200]); sid=d.get('session_id',''); print(f'MSG={msg}'); print(f'SID={sid}')\"); open -g \"notchsogood://notify?type=complete&message=$MSG&session_id=$SID\"; (sleep 6 && open -g \"notchsogood://session_end?session_id=$SID\") &","timeout":5000}]}]
HOOKEOF

# PreToolUse hook: sends tool details to Notch So Good's permission server.
# The hook checks Claude Code's own permission settings first — if a tool is already
# allowed (in settings.json or settings.local.json), it auto-approves without prompting.
# Only tools that Claude Code would ALSO ask about get shown in the notch UI.
# If the app isn't running, curl fails immediately and hook outputs nothing (normal Claude flow).
read -r -d '' PRETOOLUSE_HOOK << 'HOOKEOF' || true
[{"matcher":"","hooks":[{"type":"command","command":"INPUT=$(cat); PORT=$(cat /tmp/notchsogood.port 2>/dev/null); if [ -n \"$PORT\" ]; then RESULT=$(echo \"$INPUT\" | python3 -c \"\nimport sys, json, fnmatch, os, re\n\nd = json.load(sys.stdin)\ntn = d.get('tool_name', '')\nti = d.get('tool_input', {})\nsid = d.get('session_id', '')\n\n# Extract a human-readable summary of the tool input\nif tn == 'Bash':\n    summary = ti.get('command', '')\nelif tn in ('Edit', 'Write', 'Read', 'NotebookEdit'):\n    summary = ti.get('file_path', '')\nelif tn == 'Grep':\n    summary = ti.get('pattern', '')\nelse:\n    summary = json.dumps(ti)[:200] if isinstance(ti, dict) else str(ti)[:200]\n\n# --- Settings paths (global + global local) ---\nsettings_paths = [\n    os.path.expanduser('~/.claude/settings.json'),\n    os.path.expanduser('~/.claude/settings.local.json'),\n]\n\n# --- 1. Check dangerous mode / bypass permissions ---\nfor p in settings_paths:\n    try:\n        with open(p) as f:\n            s = json.load(f)\n        if s.get('skipDangerousModePermissionPrompt') or s.get('dangerouslySkipPermissions'):\n            print('APPROVE')\n            sys.exit(0)\n    except: pass\n\n# --- 2. Built-in safe tools (read-only, questions, navigation) ---\nSAFE = {\n    'Read','Glob','Grep','LSP','Agent','ToolSearch',\n    'EnterPlanMode','ExitPlanMode','EnterWorktree','ExitWorktree',\n    'TaskGet','TaskList','TaskOutput','TaskCreate','TaskUpdate','TaskStop',\n    'CronList','ListMcpResourcesTool','ReadMcpResourceTool',\n    'Skill','SendMessage','WebFetch','WebSearch','NotebookEdit',\n    'mcp__conductor__AskUserQuestion','mcp__conductor__DiffComment',\n    'mcp__conductor__GetTerminalOutput','mcp__conductor__GetWorkspaceDiff',\n}\nif tn in SAFE:\n    print('APPROVE')\n    sys.exit(0)\n\n# --- 3. MCP read-only heuristic ---\n# If the MCP function name contains read-only keywords, auto-approve.\n# This avoids needing to hardcode every MCP server's tool list.\nif tn.startswith('mcp__'):\n    parts = tn.split('__')\n    func = parts[-1].lower() if len(parts) >= 3 else ''\n    read_only = ['get_','list_','search_','read_','find_','query_','resolve','snapshot','watch','fetch']\n    if any(kw in func for kw in read_only):\n        print('APPROVE')\n        sys.exit(0)\n\n# --- 4. Check Claude Code permission allow lists ---\nallowed = []\nfor p in settings_paths:\n    try:\n        with open(p) as f:\n            s = json.load(f)\n        allowed.extend(s.get('permissions', {}).get('allow', []))\n    except: pass\n\nfor rule in allowed:\n    if '(' in rule:\n        # Pattern rule: 'Bash(git commit:*)'\n        rtn = rule[:rule.index('(')]\n        rpat = rule[rule.index('(')+1:rule.rindex(')')]\n        if tn != rtn:\n            continue\n        if rpat == '*':\n            print('APPROVE')\n            sys.exit(0)\n        if rpat.endswith(':*'):\n            prefix = rpat[:-2]\n            if summary.startswith(prefix):\n                print('APPROVE')\n                sys.exit(0)\n        elif fnmatch.fnmatch(summary, rpat):\n            print('APPROVE')\n            sys.exit(0)\n    else:\n        # Simple rule: 'Edit' (exact) or 'mcp__pencil' (prefix for namespace)\n        if tn == rule:\n            print('APPROVE')\n            sys.exit(0)\n        # Prefix match: 'mcp__pencil' allows 'mcp__pencil__batch_design'\n        if tn.startswith(rule + '__'):\n            print('APPROVE')\n            sys.exit(0)\n\n# --- Not auto-approved — send to permission server ---\nprint('ASK|' + json.dumps({'tool_name': tn, 'tool_input': summary[:200], 'session_id': sid}))\n\"); if [ \"$RESULT\" = \"APPROVE\" ]; then echo '{\"decision\":\"approve\"}'; elif echo \"$RESULT\" | grep -q '^ASK|'; then BODY=$(echo \"$RESULT\" | sed 's/^ASK|//'); RESP=$(echo \"$BODY\" | curl -s --max-time 120 -X POST -H 'Content-Type: application/json' -d @- \"http://localhost:$PORT/permission\" 2>/dev/null); [ -n \"$RESP\" ] && echo \"$RESP\"; fi; fi","timeout":300000}]}]
HOOKEOF

# Merge hooks into settings using python3 (replaces jq dependency)
UPDATED=$(python3 -c "
import json, sys

settings_path = sys.argv[1]
start_hook = json.loads(sys.argv[2])
notif_hook = json.loads(sys.argv[3])
stop_hook = json.loads(sys.argv[4])
pretooluse_hook = json.loads(sys.argv[5])

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
hooks['SessionStart'] = start_hook
hooks['Notification'] = notif_hook
hooks['Stop'] = stop_hook
hooks['PreToolUse'] = pretooluse_hook
settings['hooks'] = hooks

print(json.dumps(settings, indent=2))
" "$SETTINGS_FILE" "$START_HOOK" "$NOTIFICATION_HOOK" "$STOP_HOOK" "$PRETOOLUSE_HOOK")

if [ -z "$UPDATED" ]; then
    echo "Error: Failed to update settings — restoring backup"
    LATEST_BACKUP=$(ls -t "$SETTINGS_FILE.backup."* 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then cp "$LATEST_BACKUP" "$SETTINGS_FILE"; fi
    exit 1
fi

echo "$UPDATED" > "$SETTINGS_FILE"

echo "Claude Code hooks installed!"
echo "  Settings: $SETTINGS_FILE"
echo "  Hooks: SessionStart, Notification, Stop, PreToolUse"
echo ""
echo "  Make sure Notch So Good is running to receive notifications."
echo "  Permission approvals work automatically when the app is running."
