#!/usr/bin/env bash
#
# 使用前置说明：
# 1. `export OPENLIST_PASSWORD=` 密码变量设置
# 2.
#
# Dependencies: curl, jq, openssl

set -e
set -o pipefail

# --- Configuration ---
# TODO: Replace with your Alist server details.
OPENLIST_URL="${OPENLIST_URL:-https://drive.ooooo.space}"
OPENLIST_USERNAME="${OPENLIST_USERNAME:-picbed}"
OPENLIST_PASSWORD="${OPENLIST_PASSWORD:-}" # The raw password, the script will hash it.
PICBED_BASE_DIR="${PICBED_BASE_DIR:-/openlist}"

# --- Globals ---
TOKEN_FILE="/tmp/openlist-$OPENLIST_USERNAME-token"
_OPENLIST_TOKEN=""

# --- Colors ---
C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'

# --- Logging ---
log() {
    local message="$*"
    if [[ "$message" == ERROR:* ]]; then
        echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] - ${C_RED}${message}${C_RESET}" >&2
    else
        echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] - ${message}" >&2
    fi
}

# --- JWT Handling ---

# Decodes the payload of a JWT token.
# Usage: jwt_decode <token>
jwt_decode() {
    local token=$1
    local payload
    if ! payload=$(echo "$token" | cut -d. -f2); then
        log "ERROR: Invalid token format."
        return 1
    fi

    # Replace URL-safe characters and decode
    local decoded_payload
    if ! decoded_payload=$(echo "$payload" | tr '_-' '/+' | base64 --decode 2>/dev/null); then
        log "ERROR: Failed to decode JWT payload. The token might be corrupted."
        return 1
    fi
    echo "$decoded_payload"
}

# Checks if a JWT token is expired.
# Returns 0 if not expired, 1 if expired or invalid.
# Usage: is_token_expired <token>
is_token_expired() {
    local token=$1
    if [[ -z "$token" ]]; then
        return 1 # Token is empty, so it's "expired"
    fi

    local payload
    if ! payload=$(jwt_decode "$token"); then
        log "Token is invalid or could not be decoded."
        return 1
    fi

    local exp
    if ! exp=$(echo "$payload" | jq -r '.exp // 0'); then
        log "Could not extract expiration time from token."
        return 1
    fi

    local current_time
    current_time=$(date +%s)

    if [[ "$exp" -le "$current_time" ]]; then
        log "Token is expired."
        return 1 # Expired
    else
        log "Token is still valid."
        return 0 # Not expired
    fi
}

# --- Alist API ---

# Logs into Alist and retrieves a new token.
# The new token is stored in the TOKEN_FILE and the global _OPENLIST_TOKEN variable.
login() {
    log "Attempting to log in to Alist..."

    # Hash the password as required by Alist API
    local hashed_password
    hashed_password=$(printf "%s" "${OPENLIST_PASSWORD}-https://github.com/alist-org/alist" | openssl dgst -sha256 | cut -d' ' -f2)

    local body
    body=$(jq -n \
        --arg username "$OPENLIST_USERNAME" \
        --arg password "$hashed_password" \
        '{username: $username, password: $password}')

    local response
    if ! response=$(curl -s -X POST "${OPENLIST_URL}/api/auth/login/hash" \
        -H "Content-Type: application/json" \
        -d "$body"); then
        log "ERROR: Login request failed."
        return 1
    fi

    local code
    code=$(echo "$response" | jq -r '.code')

    if [[ "$code" != "200" ]]; then
        local message
        message=$(echo "$response" | jq -r '.message')
        log "ERROR: Alist login failed. Code: $code, Message: $message"
        return 1
    fi

    _OPENLIST_TOKEN=$(echo "$response" | jq -r '.data.token')
    if [[ -z "$_OPENLIST_TOKEN" ]]; then
        log "ERROR: Failed to retrieve token from login response."
        return 1
    fi

    echo "$_OPENLIST_TOKEN" >"$TOKEN_FILE"
    log "Successfully logged in and saved new token."
}

# Ensures a valid token is available, refreshing it if necessary.
# The valid token will be stored in the global _OPENLIST_TOKEN variable.
ensure_token() {
    if [[ -n "$_OPENLIST_TOKEN" ]] && is_token_expired "$_OPENLIST_TOKEN"; then
        log "Using pre-loaded valid token."
        return 0
    fi

    if [[ -f "$TOKEN_FILE" ]]; then
        _OPENLIST_TOKEN=$(cat "$TOKEN_FILE")
        # The logic is inverted here. is_token_expired returns 0 (success) if the token is NOT expired.
        # We should only log in if the token IS expired (returns 1).
        if ! is_token_expired "$_OPENLIST_TOKEN"; then
            login
        else
            log "Using cached token."
        fi
    else
        log "Token file not found."
        login
    fi

    if [[ -z "$_OPENLIST_TOKEN" ]]; then
        log "CRITICAL: Could not obtain a valid token."
        return 1
    fi
}

# URL-encodes a string.
# Usage: url_encode <string>
url_encode() {
    local encoded
    encoded=$(perl -MURI::Escape -e 'print uri_escape($ARGV[0], "^a-zA-Z0-9.~_/-")' -- "$1")
    printf "%s" "$encoded"
}

# Uploads a file to a specified directory in Alist.
# Usage: upload <local_file_path> <remote_directory> [new_filename]
# Example: upload ./myfile.txt /Public/uploads
# Example: upload ./myfile.txt /Public/uploads my-remote-file.txt
upload() {
    local local_file=$1
    local remote_dir=$2
    local new_filename=$3

    if [[ -z "$local_file" || -z "$remote_dir" ]]; then
        log "Usage: upload <local_file_path> <remote_directory> [new_filename]"
        return 1
    fi

    if [[ ! -f "$local_file" ]]; then
        log "ERROR: Local file not found: $local_file"
        return 1
    fi

    ensure_token || return 1

    local filename
    if [[ -n "$new_filename" ]]; then
        filename="$new_filename"
    else
        filename=$(basename "$local_file")
    fi

    # Ensure remote_dir ends with a slash
    [[ "$remote_dir" != */ ]] && remote_dir+="/"
    local remote_path="${remote_dir}${filename}"

    log "Uploading '$local_file' to '$remote_path'..."

    local response
    if ! response=$(curl -s -X PUT "${OPENLIST_URL}/api/fs/form" \
        -H "Authorization: $_OPENLIST_TOKEN" \
        -H "File-Path: $remote_path" \
        -F "file=@$local_file"); then
        log "ERROR: File upload request failed."
        return 1
    fi

    local code
    code=$(echo "$response" | jq -r '.code')

    if [[ "$code" == "200" ]]; then
        log "Successfully started upload for '$filename'."
        return 0
    else
        local message
        message=$(echo "$response" | jq -r '.message')
        log "ERROR: File upload failed. Code: $code, Message: $message"
        echo "$response" | jq .
        return 1
    fi
}

# Function to display usage information
usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  upload <file_path> <remote_path>    上传文件至指定远程路径。
  upload_to_picbed <file_path>        以随机名称上传文件至图床目录。
  help                                显示此帮助消息。

Environment variables for alist:
EOF
    exit 1
}

# Function to upload a file to the picbed
upload_to_picbed() {
    if [ -z "$1" ]; then
        log "Error: File path is required."
        usage
    fi

    ensure_token || return 1

    local file_path="$1"
    local filename
    filename=$(basename -- "$file_path")
    local extension="${filename##*.}"
    local filename_no_ext="${filename%.*}"

    # Generate 8 random alphanumeric characters
    local random_str
    random_str=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)

    local current_month
    current_month=$(date +%Y-%m)
    local new_filename="${filename_no_ext}_${random_str}.${extension}"
    local picbed_dir="${PICBED_BASE_DIR}/${current_month}"

    log "Uploading ${file_path} to ${picbed_dir} with new name ${new_filename}..."
    if upload "$file_path" "$picbed_dir" "$new_filename"; then
        local url_path
        url_path=$(url_encode "picbed/openlist/${current_month}/${new_filename}")
        local full_url="${OPENLIST_URL}/p/${url_path}"
        echo -e "Upload successful. URL: ${C_GREEN}${full_url}${C_RESET}"

        # Format as Markdown and copy to clipboard
        local markdown_link="![](${full_url})"
        echo -n "$markdown_link" | pbcopy
        log "${C_YELLOW}Markdown link copied to clipboard.${C_RESET}"
    else
        log "Error: Upload failed."
        return 1
    fi
}

# --- Main Execution ---
# This part of the script demonstrates how to use the 'upload' function.
# To use this script as a library of functions, you can source it and then
# call the functions directly from your shell.
#
# Example:
# source ./openlist.sh
# upload ./my-local-file.zip /Public/backups
#
# The main function is added to allow direct execution for testing.
main() {
    if [[ $# -eq 0 ]]; then
        usage
        return 1
    fi

    local command="$1"
    shift

    case "$command" in
    upload)
        upload "$@"
        ;;
    upload_to_picbed)
        upload_to_picbed "$@"
        ;;
    help)
        usage
        ;;
    *)
        log "ERROR: Unknown command: $command"
        usage
        ;;
    esac
}

# If the script is executed directly (not sourced), run the main function.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
