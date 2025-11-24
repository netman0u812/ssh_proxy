#!/bin/bash
###############################################################################
# Script Name: ssh_proxy.sh
#
# Capabilities:
# 1. Interactive or CLI-based SSH session through a proxy using SSH keys.
# 2. Supports separate usernames for proxy and remote hosts.
# 3. Allows execution of a single remote command (--remote-cmd).
# 4. Allows execution of multiple commands from a file (--cmd-file).
# 5. Stop-on-error option (--stop-on-error) for command files.
# 6. Logs all connection events daily in the user's directory with timestamps.
# 7. Provides a help summary (-h) with usage and examples.
# 8. Debug mode (-d) prints all events to stdout in addition to logging.
###############################################################################

USER_DIR_BASE="/home/users"
SSH_KEY="$HOME/.ssh/id_rsa"
PROXY_LIST=("proxy1.example.com" "proxy2.example.com")
REMOTE_LIST=("remote1.example.com" "remote2.example.com")
DEBUG=false
STOP_ON_ERROR=false

show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --user <username>          Specify SSH username for both proxy and remote"
    echo "  --proxy-user <username>    Specify SSH username for proxy only"
    echo "  --remote-user <username>   Specify SSH username for remote only"
    echo "  --proxy <proxy_host>       Specify proxy host"
    echo "  --remote <remote_host>     Specify remote host"
    echo "  --remote-cmd "<command>"   Run a single command on the remote host"
    echo "  --cmd-file <path>          Run multiple commands from a file on the remote host"
    echo "  --stop-on-error            Stop executing commands from file on first failure"
    echo "  -d                         Enable debug mode (prints events to stdout)"
    echo "  -h                         Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --user alice --proxy proxy1.example.com --remote remote2.example.com"
    echo "  $0 --proxy-user bob --remote-user alice --proxy proxy1.example.com --remote remote2.example.com --remote-cmd "uptime""
    echo "  $0 --proxy-user bob --remote-user alice --proxy proxy1.example.com --remote remote2.example.com --cmd-file /tmp/commands.txt --stop-on-error"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user) USER_ID="$2"; PROXY_USER="$2"; REMOTE_USER="$2"; shift 2 ;;
        --proxy-user) PROXY_USER="$2"; shift 2 ;;
        --remote-user) REMOTE_USER="$2"; shift 2 ;;
        --proxy) PROXY_HOST="$2"; shift 2 ;;
        --remote) REMOTE_HOST="$2"; shift 2 ;;
        --remote-cmd) REMOTE_CMD="$2"; shift 2 ;;
        --cmd-file) CMD_FILE="$2"; shift 2 ;;
        --stop-on-error) STOP_ON_ERROR=true; shift ;;
        -d) DEBUG=true; shift ;;
        -h) show_help ;;
        *) echo "Unknown option: $1"; show_help ;;
    esac
done

if [ -z "$USER_ID" ] && [ -z "$REMOTE_USER" ]; then
    read -p "Enter the user identity for SSH: " USER_ID
    PROXY_USER="$USER_ID"
    REMOTE_USER="$USER_ID"
fi

USER_DIR="$USER_DIR_BASE/${USER_ID:-$REMOTE_USER}"
if [ ! -d "$USER_DIR" ]; then
    echo "Error: User '${USER_ID:-$REMOTE_USER}' is not a member of the users directory group."
    exit 1
fi

read -s -p "Enter your password (for sudo or other use): " USER_PASS
echo

if [ -z "$PROXY_HOST" ]; then
    echo "Select a proxy host:"
    select PROXY_HOST in "${PROXY_LIST[@]}"; do
        [ -n "$PROXY_HOST" ] && break
    done
fi

if [ -z "$REMOTE_HOST" ]; then
    echo "Select a remote host:"
    select REMOTE_HOST in "${REMOTE_LIST[@]}"; do
        [ -n "$REMOTE_HOST" ] && break
    done
fi

if [ ! -f "$SSH_KEY" ]; then
    echo "Error: SSH key not found at $SSH_KEY"
    exit 2
fi

LOG_FILE="$USER_DIR/ssh_proxy_connection_log_$(date +%m-%d-%y).log"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log_event() {
    local MESSAGE="$1"
    echo "$MESSAGE" >> "$LOG_FILE"
    $DEBUG && echo "$MESSAGE"
}

MODE="INTERACTIVE"
if [ -n "$CMD_FILE" ]; then
    MODE="COMMAND FILE: $CMD_FILE"
elif [ -n "$REMOTE_CMD" ]; then
    MODE="COMMAND: $REMOTE_CMD"
fi

log_event "$(date '+%Y-%m-%d %H:%M:%S') | ProxyUser: $PROXY_USER | RemoteUser: $REMOTE_USER | Proxy: $PROXY_HOST | Remote: $REMOTE_HOST | SSH Key: $SSH_KEY | Mode: $MODE | Status: ATTEMPTING"

if [ -n "$CMD_FILE" ]; then
    while IFS= read -r CMD; do
        [ -z "$CMD" ] && continue
        log_event "$(date '+%Y-%m-%d %H:%M:%S') | Executing Command: $CMD"
        ssh -i "$SSH_KEY" -J "$PROXY_USER@$PROXY_HOST" "$REMOTE_USER@$REMOTE_HOST" "$CMD"
        CMD_EXIT=$?
        if [ $CMD_EXIT -eq 0 ]; then
            log_event "$(date '+%Y-%m-%d %H:%M:%S') | Command: $CMD | Status: SUCCESS"
        else
            log_event "$(date '+%Y-%m-%d %H:%M:%S') | Command: $CMD | Status: FAILED (Exit $CMD_EXIT)"
            if $STOP_ON_ERROR; then
                log_event "$(date '+%Y-%m-%d %H:%M:%S') | Stop-on-error triggered. Halting execution."
                exit $CMD_EXIT
            fi
        fi
    done < "$CMD_FILE"
elif [ -n "$REMOTE_CMD" ]; then
    ssh -i "$SSH_KEY" -J "$PROXY_USER@$PROXY_HOST" "$REMOTE_USER@$REMOTE_HOST" "$REMOTE_CMD"
    SSH_EXIT_CODE=$?
else
    ssh -i "$SSH_KEY" -J "$PROXY_USER@$PROXY_HOST" "$REMOTE_USER@$REMOTE_HOST"
    SSH_EXIT_CODE=$?
fi

if [ -z "$CMD_FILE" ]; then
    if [ $SSH_EXIT_CODE -ne 0 ]; then
        log_event "$(date '+%Y-%m-%d %H:%M:%S') | Status: FAILED (Exit $SSH_EXIT_CODE)"
    else
        log_event "$(date '+%Y-%m-%d %H:%M:%S') | Status: SUCCESS"
    fi
fi
