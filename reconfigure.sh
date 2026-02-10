#!/bin/bash
# Interactive reconfiguration for the wrapper script.
# Updates the config block at the top of the wrapper and optionally renames it,
# then updates references to the wrapper filename in the repo.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Scope reference updates to this repo (directory containing the wrapper)
REPO_ROOT="$SCRIPT_DIR"

# Find the wrapper script (contains config block; exclude self)
find_wrapper() {
    local found=""
    for f in "$SCRIPT_DIR"/*.sh; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = "reconfigure.sh" ] && continue
        if grep -q '## Begin Config Section' "$f" 2>/dev/null && grep -q '## End Config Section' "$f" 2>/dev/null; then
            if [ -n "$found" ]; then
                echo "Multiple scripts with config block found. Using: $found" >&2
                echo "$found"
                return
            fi
            found="$f"
        fi
    done
    echo "$found"
}

WRAPPER="$(find_wrapper)"
if [ -z "$WRAPPER" ] || [ ! -f "$WRAPPER" ]; then
    echo "Error: No wrapper script with config block found in $SCRIPT_DIR" >&2
    exit 1
fi

# Parse current config (quoted values only; slugName/packageListFile are derived)
get_var() {
    local name="$1"
    sed -n "s/^${name}=\"\\(.*\\)\"[[:space:]]*$/\\1/p" "$WRAPPER" | head -1
}

current_displayName="$(get_var displayName)"
current_domain="$(get_var domain)"
current_repo="$(get_var repo)"
current_installedName="$(get_var installedName)"
current_binDir="$(get_var binDir)"
current_scriptDir="$(get_var scriptDir)"
current_wrapperName="$(get_var wrapperName)"
current_gitUsername="$(get_var gitUsername)"
current_gitToken="$(get_var gitToken)"

# Defaults for empty
current_displayName="${current_displayName:-NNW}"
current_domain="${current_domain:-https://github.com}"
current_repo="${current_repo:-Nackloose/nnw}"
current_installedName="${current_installedName:-nnw}"
current_binDir="${current_binDir:-/usr/bin}"
current_scriptDir="${current_scriptDir:-/etc/nnw}"
current_wrapperName="${current_wrapperName:-nnw.sh}"

echo "Reconfigure wrapper: $WRAPPER"
echo "Current wrapper filename: $current_wrapperName"
echo ""
echo "Enter new values (press Enter to keep current)."
echo ""

read -p "Display name (e.g. NNW) [$current_displayName]: " input_displayName
displayName="${input_displayName:-$current_displayName}"
slugName=$(echo "$displayName" | awk '{print tolower($0)}')

read -p "Domain (e.g. https://github.com) [$current_domain]: " input_domain
domain="${input_domain:-$current_domain}"

default_repo="Nackloose/$slugName"
read -p "Repo (owner/name) [$current_repo]: " input_repo
repo="${input_repo:-$current_repo}"

read -p "Installed command name (symlink in PATH) [$current_installedName]: " input_installedName
installedName="${input_installedName:-$current_installedName}"

read -p "binDir (where symlink is created) [$current_binDir]: " input_binDir
binDir="${input_binDir:-$current_binDir}"

default_scriptDir="/etc/$slugName"
read -p "scriptDir (where repo is installed) [$current_scriptDir]: " input_scriptDir
scriptDir="${input_scriptDir:-$current_scriptDir}"

default_wrapperName="${slugName}.sh"
read -p "Wrapper script filename [$current_wrapperName]: " input_wrapperName
wrapperName="${input_wrapperName:-$current_wrapperName}"

read -p "Git username (optional) [$current_gitUsername]: " input_gitUsername
gitUsername="${input_gitUsername:-$current_gitUsername}"

read -p "Git token (optional) [$current_gitToken]: " input_gitToken
gitToken="${input_gitToken:-$current_gitToken}"

# Build new config block (packageListFile is derived)
CONFIG_BLOCK="## Begin Config Section (use ./reconfigure.sh to change these interactively)
gitUsername=\"$gitUsername\"
gitToken=\"$gitToken\"
domain=\"$domain\"
displayName=\"$displayName\"
slugName=\$(echo \"\$displayName\" | awk '{print tolower(\$0)}')
repo=\"$repo\"
installedName=\"$installedName\"
binDir=\"$binDir\"
scriptDir=\"$scriptDir\"
packageListFile=\"\$scriptDir/.installed_packages\"
wrapperName=\"$wrapperName\"
## End Config Section. Don't edit below, unless you intend to change functionality."

# Replace config block in wrapper
end_line=$(grep -n "## End Config Section" "$WRAPPER" | head -1 | cut -d: -f1)
if [ -z "$end_line" ]; then
    echo "Error: Could not find config end marker in $WRAPPER" >&2
    exit 1
fi

{
    head -n 1 "$WRAPPER"
    echo "$CONFIG_BLOCK"
    tail -n +$((end_line + 1)) "$WRAPPER"
} > "$WRAPPER.new"
mv "$WRAPPER.new" "$WRAPPER"
chmod +x "$WRAPPER"

echo ""
echo "Config block updated in $WRAPPER"

# Sync repo and wrapper script name in raw.githubusercontent.com URLs (README, docs).
# Replace owner/repo path with configured repo; replace script name after refs/heads/main/ with configured wrapperName.
while IFS= read -r -d '' f; do
    [ "$(basename "$f")" = "reconfigure.sh" ] && continue
    changed=""
    if grep -qE 'raw\.githubusercontent\.com/[^/]+/[^/]+/' "$f" 2>/dev/null; then
        sed -i -E "s|(raw\.githubusercontent\.com/)[^/]+/[^/]+(/)|\1$repo\2|g" "$f" 2>/dev/null && changed="1"
    fi
    if grep -qE 'refs/heads/main/[^ ]+' "$f" 2>/dev/null; then
        sed -i -E "s|(refs/heads/main/)[^ ]+|\1$wrapperName|g" "$f" 2>/dev/null && changed="1"
    fi
    [ -n "$changed" ] && echo "  Updated URLs in: $f"
done < <(find "$REPO_ROOT" -type f -name "*.md" -not -path "*/.git/*" 2>/dev/null | tr '\n' '\0')

# Replace wrapper filename in repo (scripts, docs) when name changed
if [ "$current_wrapperName" != "$wrapperName" ]; then
    new_path="$SCRIPT_DIR/$wrapperName"
    if [ -f "$new_path" ] && [ "$(realpath "$new_path")" != "$(realpath "$WRAPPER")" ]; then
        echo "Error: $new_path already exists. Not renaming." >&2
        exit 1
    fi
    mv "$WRAPPER" "$new_path"
    WRAPPER="$new_path"
    echo "Renamed wrapper to: $wrapperName"

    while IFS= read -r -d '' f; do
        [ "$(basename "$f")" = "reconfigure.sh" ] && continue
        if grep -q "$current_wrapperName" "$f" 2>/dev/null; then
            sed -i "s/$(echo "$current_wrapperName" | sed 's/\./\\./g')/$(echo "$wrapperName" | sed 's/\./\\./g')/g" "$f" 2>/dev/null && echo "  Updated references in: $f"
        fi
    done < <(find "$REPO_ROOT" -type f \( -name "*.sh" -o -name "*.md" \) -not -path "*/.git/*" 2>/dev/null | tr '\n' '\0')
fi

# When reconfigure has been run, add second footnote (third-party / based-on MTX) if not already present
README_FILE="$REPO_ROOT/README.md"
if [ -f "$README_FILE" ] && ! grep -q 'This is based on \[MTX\]' "$README_FILE" 2>/dev/null; then
    MTX_REPO_URL="https://github.com/Nackloose/MTX"
    printf '\n\n---\n\n*This is based on [MTX](%s), the evolved form of Nice Network Wrapper [NNW].*' "$MTX_REPO_URL" >> "$README_FILE"
    echo "  Added third-party footnote to README.md"
fi

# Resolve installedName for display when it's a variable reference
summary_installed="$installedName"
case "$installedName" in
    \$slugName) summary_installed="$slugName (\$slugName)" ;;
    \$displayName) summary_installed="$displayName (\$displayName)" ;;
esac
echo ""
echo "Done. Wrapper: $WRAPPER"
echo "  displayName=$displayName  installedName=$summary_installed  wrapperName=$wrapperName"
