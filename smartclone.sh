#!/usr/bin/env bash

CONFIG_FILE="$HOME/.smartclonerc"
USE_HTTPS=false
GITHUB_API="https://api.github.com"
GITHUB_TOKEN="" # Global variable to store the token

declare -A ACCOUNTS

function usage() {
    cat <<EOF
Usage:
  $0 clone <repo-name> [--https] [-- <git clone flags>...]
  $0 config add <alias>
  $0 config remove <alias>
  $0 config set-token <token>
  $0 config clear-token
EOF
    exit 1
}

function add_config() {
    local alias=$1
    local full="github/$alias"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    if [[ -f "$CONFIG_FILE" ]]; then
        grep -vi "^$alias=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" || true
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
    echo "$alias=$full" >> "$CONFIG_FILE"
    echo "Added config: $alias -> $full"
}

function remove_config() {
    local alias=$1
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "No config file found."
        exit 1
    fi
    grep -vi "^$alias=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" || true
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    echo "Removed config: $alias"
}

function set_token() {
    local token=$1
    mkdir -p "$(dirname "$CONFIG_FILE")"
    if [[ -f "$CONFIG_FILE" ]]; then
        grep -vi "^GITHUB_TOKEN=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" || true
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
    echo "GITHUB_TOKEN=$token" >> "$CONFIG_FILE"
    echo "GitHub Personal Access Token set."
}

function clear_token() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "No config file found."
        exit 1
    fi
    grep -vi "^GITHUB_TOKEN=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" || true
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    echo "GitHub Personal Access Token cleared."
}


function load_accounts() {
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" || -z "$value" ]] && continue
            if [[ "$key" == "GITHUB_TOKEN" ]]; then
                GITHUB_TOKEN="$value"
            else
                ACCOUNTS["$key"]="$value"
            fi
        done < "$CONFIG_FILE"
    fi
}

function search_github() {
    local repo_name=$1
    local curl_args=("-s")

    if [[ -n "$GITHUB_TOKEN" ]]; then
        curl_args+=("-H" "Authorization: token $GITHUB_TOKEN")
    fi

    curl "${curl_args[@]}" "$GITHUB_API/search/repositories?q=${repo_name}+fork:true&per_page=50" |
        jq -r '.items[] |
        [
            .name,
            .owner.login,
            (if .private then "private" else "public" end), # Added visibility column
            (if .fork then "fork" else "original" end),
            .html_url
        ] | @tsv'
}

function format_url() {
    local url=$1
    if $USE_HTTPS; then
        echo "$url"
    else
        # Convert https://github.com/owner/repo to git@github.com:owner/repo.git
        local repo_path=${url#https://github.com/}
        echo "git@github.com:${repo_path}.git"
    fi
}

function prioritise_accounts() {
    local input="$1"
    local prioritized=()
    local others=()

    # Updated to read 5 fields: repo_name owner visibility type origin_url
    while IFS=$'\t' read -r repo_name owner visibility type origin_url; do
        local match=false
        for alias in "${!ACCOUNTS[@]}"; do
            config_owner=${ACCOUNTS[$alias]##*/}
            if [[ "${owner,,}" == "${config_owner,,}" ]]; then
                match=true
                break
            fi
        done

        origin_url=$(format_url "$origin_url")
        # Ensure the line format matches the fields read
        line="${repo_name}\t${owner}\t${visibility}\t${type}\t${origin_url}"

        if $match; then
            prioritized+=("$line")
        else
            others+=("$line")
        fi
    done <<< "$input"

    {
        for line in "${prioritized[@]}"; do echo -e "$line"; done
        for line in "${others[@]}"; do echo -e "$line"; done
    }
}

function format_table_fixed_width() {
    local input="$1"
    echo -e "$input" | awk -F'\t' '
    {
        for (i=1; i<=NF; i++) {
            if (length($i) > max[i]) max[i] = length($i)
            rows[NR,i] = $i
        }
        max_nf = NF
        row_count = NR
    }
    END {
        for (r=1; r<=row_count; r++) {
            line = ""
            for (c=1; c<=max_nf; c++) {
                format = "%-" max[c] "s"
                line = line sprintf(format, rows[r,c])
                if (c < max_nf) line = line "  "
            }
            print line
        }
    }
    '
}

function interactive_select() {
    local input="$1"
    local header_text
    # Updated header text to include "Visibility" column
    header_text=$(printf "Repo Name\tOwner\tVisibility\tType\tOrigin URL")

    local formatted_table
    formatted_table=$(format_table_fixed_width "$input")

    echo "$formatted_table" | fzf --header="$header_text" --border --ansi
}

function get_clone_url() {
    local full_name=$1
    if $USE_HTTPS; then
        echo "https://github.com/$full_name.git"
    else
        echo "git@github.com:$full_name.git"
    fi
}

function clone_repo() {
    local repo=$1
    shift
    local clone_flags=("$@")
    local clone_url
    clone_url=$(get_clone_url "$repo")
    echo "Cloning $repo from $clone_url with flags: ${clone_flags[*]}"
    git clone "${clone_flags[@]}" "$clone_url"
}

function main() {
    load_accounts

    if [[ $# -lt 1 ]]; then
        usage
    fi

    case "$1" in
        config)
            if [[ $# -lt 2 ]]; then
                usage
            fi
            case "$2" in
                add)
                    if [[ $# -ne 3 ]]; then usage; fi
                    add_config "$3"
                    ;;
                remove)
                    if [[ $# -ne 3 ]]; then usage; fi
                    remove_config "$3"
                    ;;
                set-token)
                    if [[ $# -ne 3 ]]; then usage; fi
                    set_token "$3"
                    ;;
                clear-token)
                    if [[ $# -ne 2 ]]; then usage; fi
                    clear_token
                    ;;
                *)
                    usage
                    ;;
            esac
            exit 0
            ;;
        clone)
            if [[ $# -lt 2 ]]; then
                usage
            fi

            local repo_name=""
            local clone_flags=()
            USE_HTTPS=false

            shift # remove 'clone'
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --https)
                        USE_HTTPS=true
                        shift
                        ;;
                    --)
                        shift
                        clone_flags=("$@")
                        break
                        ;;
                    *)
                        if [[ -z "$repo_name" ]]; then
                            repo_name="$1"
                        else
                            echo "Unexpected argument before --: $1"
                            usage
                        fi
                        shift
                        ;;
                esac
            done

            if [[ -z "$repo_name" ]]; then
                usage
            fi

            RAW_RESULTS=$(search_github "$repo_name")
            PRIORITISED=$(prioritise_accounts "$RAW_RESULTS")
            FORMATTED=$(format_table_fixed_width "$PRIORITISED")

            SELECTED_LINE=$(interactive_select "$FORMATTED")

            if [[ -n "$SELECTED_LINE" ]]; then
                # Extract repo and owner from selected line by whitespace.
                # Note: The format is now "Repo Name Owner Visibility Type Origin URL"
                # We still only need the first two columns (Repo Name and Owner) to form SELECTED_REPO.
                REPO_NAME_ONLY=$(echo "$SELECTED_LINE" | awk '{print $1}')
                OWNER_NAME=$(echo "$SELECTED_LINE" | awk '{print $2}')
                SELECTED_REPO="${OWNER_NAME}/${REPO_NAME_ONLY}"
                clone_repo "$SELECTED_REPO" "${clone_flags[@]}"
            else
                echo "No repository selected."
                exit 1
            fi
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
