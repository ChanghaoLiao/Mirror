# Local function calling

Mirror executes local operations without a model, API key or Mirror cloud service. The host Agent still pays for its own reasoning, instructions and tool results. This is not a promise of an entirely free workflow.

## Choose one integration

- Agents with local shell tools: use `../scripts/mirror.sh` as described in SKILL.md. No Python dependency.
- Hosts registering function tools: load `function-tools.json`. It contains 15 strict Responses-style JSON function definitions. The host executes `../scripts/functions.py` on the user's Mac, using Python 3.9+. Other function-call providers may need a different outer schema envelope. Tested local execution does not certify every Agent platform.

The standalone toolkit includes both `mirror` and `mirror-setup` skills; install both together using the host's skill-directory mechanism. No official marketplace membership is required. The desktop can be supplied in the complete bundle or fetched from the fixed GitHub preview. Initial `mirror_status` with `launch:true` installs the pinned preview when the app is absent; follow-up `launch:false` never installs or restarts. The preview verifies SHA256 and the exact sealed CDHash, preserves/adds quarantine and returns `manual_open_required` until the human completes macOS first-open approval. It is explicitly not Apple notarized. The separate production installer still requires Developer ID/notarization and is not downgraded.

## Host dispatch

Register only the functions relevant to the task to reduce context overhead. Schema loading does not launch Mirror. Tool arguments are JSON objects, never shell commands. Nullable fields must be present with null when unused; every object disallows extra fields. The adapter validates again before running the native helper.

```python
# This runs inside a local host that already owns the Agent/model connection.
# tool_name and arguments are the host's received function-call data.
import json
import subprocess
import sys

def call_mirror(adapter_path, tool_name, arguments):
    if tool_name not in {t["name"] for t in json.loads(subprocess.check_output(
        [sys.executable, adapter_path, "--tools"], text=True
    ))}:
        raise ValueError("Unknown Mirror function")
    process = subprocess.run(
        [sys.executable, adapter_path, tool_name],
        input=json.dumps(arguments, ensure_ascii=False),
        text=True, capture_output=True, timeout=660, check=False,
    )
    return json.loads(process.stdout)  # Error receipts are valid tool results too.
```

If the host already knows a specific installed app, append `--app` and that verified absolute .app path to the argument vector. Do not expose arbitrary executable paths as model tool parameters. The native helper verifies the bundle and executable before use. Never interpolate input into shell code. Do not parallelize mutations: one operation can invalidate another's revision.

## Example arguments

1. `mirror_status`: `{"launch":true,"request_id":null}` on initial user-authorized use. Follow-up status uses `launch:false` so a human quit remains final.
2. Given an actual snapshot revision of 7 and a confirmed conversation ID, `mirror_open`: `{"revision":7,"window":null,"conversation":"confirmed-conversation-id","message":null,"new":false,"request_id":null}`. This is an example ID, not a lookup by title.
3. While `contentStatus` is loading, inspect status at a modest interval. Stop on completion, failure, pause, missing window or app termination. No background model polling loop is part of Mirror.

Every mutation requires the last observed revision and is sent once. The adapter adds a UUID requestID when null is supplied. Errors retain the receipt where possible. A timeout may mean the native operation completed; do not retry under a fresh ID. On `revision_conflict` or `agent_paused`, stop the pending action. The Agent cannot resume itself, grant permissions or override human binding.

Returned window IDs and metadata are private. Neither this adapter nor the native command response returns conversation bodies. Copy writes the local clipboard only when requested. A successful open is not proof of completed reading or binding; inspect both states independently. Use the full [command reference](commands.md) for result meanings and geometry.

## Scope

No new models, subscriptions, API credentials, arbitrary-code function, history export, remote control service or auto-upgrade is introduced. A non-Codex controlling Agent must receive confirmed conversation/message IDs through an authorized lookup; it does not gain support for its own history files. A cloud host without a Mac-side executor cannot call local windows simply by loading these schemas.

Strict schema conventions follow the [function-calling documentation](https://developers.openai.com/api/docs/guides/function-calling#strict-mode). This adapter is independent; schemas do not imply OpenAI endorsement or automatic tool registration.
