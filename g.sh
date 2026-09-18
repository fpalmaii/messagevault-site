#!/bin/sh
# MessageVault - GitHub SSH auth setup for the MacinCloud Mac (TX073).
# Published temporarily; delete after use.
#
# Safe to run more than once. It never deletes a file, never overwrites an
# existing key, and never force-pushes or resets anything.
#
# Run it twice: once to create the key, then again after you register that key
# on GitHub. The second run does the pull.

set -u

REPO_DIR="$HOME/Desktop/MessageVault"
KEY="$HOME/.ssh/github_messagevault"

echo "== MessageVault Mac setup =="

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Trust github.com up front, so git never stops to ask an interactive question.
if ! grep -q "^github.com " "$HOME/.ssh/known_hosts" 2>/dev/null; then
    ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
    echo "-- added github.com to known_hosts"
fi

# Generate only if absent. An existing key is left completely alone.
if [ ! -f "$KEY" ]; then
    ssh-keygen -t ed25519 -C "messagevault-macincloud-tx073" -f "$KEY" -N "" -q
    echo "-- generated new key"
else
    echo "-- reusing existing key"
fi
chmod 600 "$KEY"

# Tell ssh to use this key for github.com.
if ! grep -q "github_messagevault" "$HOME/.ssh/config" 2>/dev/null; then
    printf '\nHost github.com\n  HostName github.com\n  User git\n  IdentityFile %s\n  IdentitiesOnly yes\n' "$KEY" >> "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    echo "-- wrote ssh config entry"
fi

if [ ! -d "$REPO_DIR" ]; then
    echo "!! repo not found at $REPO_DIR"
    exit 1
fi

cd "$REPO_DIR" || exit 1
git remote set-url origin git@github.com:fpalmaii/MessageVault.git

# Already registered on GitHub?
if ssh -o BatchMode=yes -o ConnectTimeout=15 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "-- GitHub auth OK"
    echo
    echo "== local state before pull =="
    git status --short --branch

    git fetch origin
    git branch --set-upstream-to=origin/main main >/dev/null 2>&1

    echo
    echo "== pulling =="
    if git pull --ff-only; then
        echo
        echo "== now at =="
        git log --oneline -3
        echo
        echo "== 1.5 files present? =="
        ls -l MessageVault/Migrations.swift MessageVault/TagBackfill.swift 2>&1
        echo
        echo "DONE - ready to build in Xcode."
    else
        echo
        echo "!! pull did not fast-forward. Local state above shows why."
        echo "!! Nothing was changed. Send Claude a screenshot of this."
    fi
else
    echo "-- remote switched to SSH; key not registered on GitHub yet"
    echo
    echo "=================================================================="
    echo "  NEXT STEP - copy the single line below."
    echo
    echo "  Open this in Safari or Chrome ON THIS MAC (paste works locally):"
    echo "      https://github.com/settings/ssh/new"
    echo
    echo "  Title:    MacinCloud TX073"
    echo "  Key type: Authentication Key"
    echo "  Key:      paste the line below"
    echo "=================================================================="
    echo
    cat "$KEY.pub"
    echo
    echo "Then run:  sh g.sh    (again - it will do the pull)"
fi
