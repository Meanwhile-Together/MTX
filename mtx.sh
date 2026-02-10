#!/bin/bash
## Begin Config Section (use ./reconfigure.sh to change these interactively)
gitUsername=""
gitToken=""
domain="https://github.com"
displayName="MTX"
slugName=$(echo "$displayName" | awk '{print tolower($0)}')
repo="Meanwhile-Together/MTX"
installedName="$slugName"
binDir="/usr/bin"
scriptDir="/etc/$slugName"
packageListFile="$scriptDir/.installed_packages"
wrapperName="mtx.sh"
## End Config Section. Don't edit below, unless you intend to change functionality.

# Get version from git if available
if [ -d "$scriptDir/.git" ]; then
    NNW_VERSION=$(git -C "$scriptDir" describe --tags 2>/dev/null || git -C "$scriptDir" rev-parse --short HEAD)
else
    NNW_VERSION="unknown"
fi

# Exit codes
# 0: Script completed successfully.
# 1: Error due to "uninstall" and "reinstall" flags being set at the same time.
# 2: Error due to the script directory not existing.
# 3: Error updating remote repository, and couldn't clone a new repository.
# 4: Script not found for installation
# 5: Script already installed
# 6: Script not in package list for uninstallation

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
execDir="$(pwd)"

        # Extract desc= "..." or '...' from first 30 lines of a script (for help)
        get_desc() {
            local f="$1"
            local line
            [ -f "$f" ] || return
            line=$(head -30 "$f" 2>/dev/null | grep -m1 '^desc=') || return
            line="${line#desc=}"
            line="${line#\"}"
            line="${line%\"}"
            line="${line#\'}"
            line="${line%\'}"
            [ -n "$line" ] && echo "$line"
        }

        # Preload includes (bolors etc.). Use scriptDir when installed, else dir when running from repo (before clone).
        if [ -d "$scriptDir/includes" ]; then
            for file in "$scriptDir/includes"/*.sh; do
                [ -f "$file" ] && source "$file"
            done
        elif [ -d "$dir/includes" ]; then
            for file in "$dir/includes"/*.sh; do
                [ -f "$file" ] && source "$file"
            done
        else
            # No includes yet (e.g. scriptDir not cloned). Stub so we don't call undefined functions.
            color() { echo -n "$@"; }
            c() { echo -n "$@"; }
            echoc() { echo "$@"; }
            info() { echo "[INFO] $*"; }
            success() { echo "[SUCCESS] $*"; }
            error() { echo "[ERROR] $*" >&2; }
            warn() { echo "[WARN] $*"; }
            debug() { :; }
            mtx_run() { "$@"; }
        fi
        # Ensure mtx_run is always defined (self-heal if include missing or old install)
        if ! type mtx_run &>/dev/null; then
            mtx_run() {
                local v=${MTX_VERBOSE:-1}
                if [ "$v" -le 2 ]; then
                    "$@" 1>/dev/null
                    return $?
                elif [ "$v" -eq 4 ]; then
                    ( set -x; "$@" )
                    return $?
                else
                    "$@"
                    return $?
                fi
            }
        fi

        # Create package list file if it doesn't exist (scriptDir must exist)
        if [ -d "$scriptDir" ] && [ ! -f "$packageListFile" ]; then
            touch "$packageListFile"
        fi

        #handle arguments (verbose: 1=quiet, 2=detail, 3=full output, 4=trace)
        verbose=${MTX_VERBOSE:-1}
        version=0
        uninstall=0
        reinstall=0
        hoist_target=""
        submerge=0

        printVersion() {
            if [ ! -z "$NNW_VERSION" ]; then
                echoc cyan "$(color blue NNW)[$(color yellow "$NNW_VERSION")]: as $(color magenta "$displayName")"
            fi
        }

        isScriptInstalled() {
            local script_name="$1"
            grep -q "^$script_name$" "$packageListFile"
            return $?
        }

case "$1" in
    "help")
        echo "$installedName - A helpful script wrapper"
        echo
        echo "Usage: $installedName <command> [subcommand] [options]"
        echo
        if [ -d "$scriptDir" ]; then
            echo "Commands:"
            echo
            help_labels=()
            help_descs=()
            help_sep=()
            # First-level: top-level .sh (except mtx.sh) and top-level dirs; merge same name (e.g. deploy.sh + deploy/)
            for item in "$scriptDir"/*; do
                [ -e "$item" ] || continue
                base=$(basename "$item")
                [ "$base" = "mtx.sh" ] || [ "$base" = "includes" ] || [[ "$base" == .* ]] && continue
                if [ -f "$item" ] && [[ "$base" == *.sh ]]; then
                    cmd="${base%.sh}"
                    d=$(get_desc "$item")
                    help_labels+=("  $cmd")
                    help_descs+=("${d:-}")
                    if [ -d "$scriptDir/$cmd" ]; then
                        help_sep+=(0)
                        for sub in "$scriptDir/$cmd"/*.sh; do
                            [ -f "$sub" ] || continue
                            subbase=$(basename "$sub" .sh)
                            d=$(get_desc "$sub")
                            help_labels+=("    $subbase")
                            help_descs+=("${d:-}")
                            help_sep+=(0)
                        done
                        help_sep[$((${#help_sep[@]}-1))]=1
                    else
                        help_sep+=(1)
                    fi
                elif [ -d "$item" ]; then
                    [ -f "$scriptDir/$base.sh" ] && continue
                    help_labels+=("  $base")
                    help_descs+=("")
                    help_sep+=(0)
                    for sub in "$item"/*.sh; do
                        [ -f "$sub" ] || continue
                        subbase=$(basename "$sub" .sh)
                        d=$(get_desc "$sub")
                        help_labels+=("    $subbase")
                        help_descs+=("${d:-}")
                        help_sep+=(0)
                    done
                    help_sep[$((${#help_sep[@]}-1))]=1
                fi
            done
            maxlen=0
            for i in "${!help_labels[@]}"; do
                len=${#help_labels[$i]}
                [ $len -gt $maxlen ] && maxlen=$len
            done
            for i in "${!help_labels[@]}"; do
                if [ -n "${help_descs[$i]}" ]; then
                    printf "%-*s  %s\n" "$maxlen" "${help_labels[$i]}" "${help_descs[$i]}"
                else
                    echo "${help_labels[$i]}"
                fi
                [ "${help_sep[$i]:-0}" = "1" ] && echo
            done
        else
            echo "No scripts directory at: $scriptDir"
            echo
        fi
        echo "Options:"
        echo "   --help Show this help message"
        echo "   --version Print nnw version"
        echo "   -v       Quiet: only MTX output and errors from scripts (default)"
        echo "   -vv      More detail (debug messages)"
        echo "   -vvv     Full output from scripts"
        echo "   -vvvv    Trace: print every command run"
        echo "   --update Update nnw"
        echo "   --uninstall Uninstall nnw"
        echo "   --reinstall Reinstall nnw"
        echo "   --hoist=<name> Install script as command with given name"
        echo "   --submerge Remove all hoisted instances of the current script"
        ;;
    *)
        while [[ $# -gt 0 ]]; do
            case "$1" in
            "--version")
                version=1
                debug "Version flag detected, will print version and exit"
                shift
                ;;
            -vvvv)
                verbose=4
                shift
                ;;
            -vvv)
                verbose=3
                shift
                ;;
            -vv)
                verbose=2
                shift
                ;;
            -v)
                verbose=1
                shift
                ;;
            "--verbose")
                verbose=3
                shift
                ;;
            "--uninstall")
                uninstall=1
                debug "Uninstall flag detected, will uninstall $(c yellow "$displayName")"
                shift
                ;;
            "--reinstall")
                reinstall=1
                debug "Reinstall flag detected, will reinstall $(c yellow "$displayName")"
                shift
                ;;
            --hoist=*)
                hoist_target="${1#*=}"
                debug "Hoist flag detected, will hoist script as $hoist_target"
                shift
                ;;
            "--submerge")
                submerge=1
                debug "Submerge flag detected, will remove all hoisted instances of current script"
                shift
                ;;
            *)
                break
                ;;
            esac
        done

        #check if version flag is set, if so print version and exit
        if [ $version -eq 1 ]; then
            printVersion
            exit 0
        fi

        #check if uninstall and reinstall are both set, if so exit, that can't happen
        if [ $uninstall -eq 1 ] && [ $reinstall -eq 1 ]; then
            error "Both uninstall and reinstall flags are set, this is not allowed"
            exit 1
        fi

        installWrapper() {
            if command -v sudo &>/dev/null; then
                sudo rm -rf "$scriptDir"
                sudo mkdir -p "$scriptDir"
                sudo chown $USER:$USER "$scriptDir"
            else
                rm -rf "$scriptDir"
                mkdir -p "$scriptDir"
                chown $USER:$USER "$scriptDir"
            fi
            updateCheck
            if command -v sudo &>/dev/null; then
                sudo rm -f "$binDir/$installedName"
                sudo ln -sf "$scriptDir/$wrapperName" "$binDir/$installedName" >/dev/null
                sudo chmod +x "$scriptDir/$wrapperName"
            else
                rm -f "$binDir/$installedName"
                ln -sf "$scriptDir/$wrapperName" "$binDir/$installedName" >/dev/null
                chmod +x "$scriptDir/$wrapperName"
            fi
            success "$(color magenta "$wrapperName") as $(color yellow "$displayName") installed"
            success "      As?                 '$installedName'"
            success "      Where?              $binDir/$installedName"
            success "      Repo link?          $domain/$repo"
            success "Ready to roooollout!"
        }

        updateCheck() {
            info "Checking for updates..."
            if [ ! -d "$scriptDir" ]; then
                error "Directory '$scriptDir' does not exist"
                exit 2
            fi

            if git -C "$scriptDir" remote update &>/dev/null; then
                if ! git -C "$scriptDir" diff --ignore-space-at-eol --quiet origin/main; then
                    info "Remote repository has changes."
                    shaBefore=$(git -C "$scriptDir" rev-parse HEAD)
                    info "Pre update SHA: $(color yellow "$shaBefore")"
                    info "Updating local repository..."
                    if [ $verbose -ge 3 ]; then
                        git -C "$scriptDir" fetch --all
                    else
                        git -C "$scriptDir" fetch --all --quiet
                    fi
                    if [ $verbose -ge 3 ]; then
                        git -C "$scriptDir" fetch --all
                    else
                        git -C "$scriptDir" reset --hard origin/main --quiet
                    fi
                    if command -v sudo &>/dev/null; then
                        sudo chmod +x "$scriptDir/$wrapperName"
                        sudo ln -sf "$scriptDir/$wrapperName" "$binDir/$installedName"
                    else
                        chmod +x "$scriptDir/$wrapperName"
                        ln -sf "$scriptDir/$wrapperName" "$binDir/$installedName"
                    fi
                    success "Local repository has been updated from remote repository."
                    shaNow=$(git -C "$scriptDir" rev-parse HEAD)
                    info "Post update SHA: $(color yellow "$shaNow")"
                    if [ -n "$shaBefore" ] && [ "$shaBefore" != "$shaNow" ]; then
                        info "Commits in this update:"
                        git -C "$scriptDir" log --oneline "$shaBefore..$shaNow" 2>/dev/null | sed 's/^/  /' || true
                    fi
                else
                    success "Local repository is up-to-date with remote repository."
                fi
            else
                error "Error updating remote repository. Cloning new repository..."
                git -C "$scriptDir" clone --depth 1 "$domain/$repo" "$scriptDir"
            fi
        }

        isolateScript() {

            pathSoFar="."
            pathAt=1
            for w in "$@"; do
                let pathAt++
                pathSoFar="$pathSoFar/$w"
                if [ -f "$pathSoFar.sh" ]; then
                    echo "$pathAt"
                    return 0
                fi
            done
            return 1
        }

        isolateDir() {

            pathSoFar="."
            pathAt=1
            for w in "$@"; do
                let pathAt++
                pathSoFar="$pathSoFar/$w"
                if [ -d "$pathSoFar" ]; then
                    echo "$pathAt"
                    return 0
                fi
            done
            return 1
        }

        if [ $uninstall -eq 1 ]; then
            debug "Uninstalling $(c yellow "$displayName")..."
            if command -v sudo &>/dev/null; then
                sudo rm -f "$binDir/$installedName"
            else
                rm -f "$binDir/$installedName"
            fi
            success "Uninstalled $(c yellow "$displayName")"
            exit 0
        fi

        if [ ! "$dir" == "$binDir" ]; then
            debug "Script is not in $binDir, installing wrapper..."
            installWrapper
            exit 0
        else
            #     sudo chown $USER:$USER "$scriptDir"
            debug "Script is in $binDir, checking wrapper to see if its outdated..."
            cd "$scriptDir"
            if [ -z "${MTX_SKIP_UPDATE:-}" ]; then
                updateCheck
            fi

            if [ $verbose -ge 2 ]; then
                printVersion
            fi

            cmdEndIndex=$(isolateScript "$@")
            debug "cmdEndIndex: $cmdEndIndex"
            if [ $((cmdEndIndex - 1)) -lt 0 ]; then
                debug "Wasn't a script, lets see if its a dir."
                cmdEndIndex=$(isolateDir "$@")
                if [ $((cmdEndIndex - 1)) -gt 0 ]; then
                    debug "It was a dir! Lets list the contents for the user."
                    script=${@:1:cmdEndIndex-1}
                    script="${script// //}"
                    error "Script '$script' is a directory."
                    info "Available scripts and subdirectories in this directory are:"
                    info "Scripts are $(color green "green") and directories are $(color yellow "yellow")"
                    for file in "$script"/*; do
                        if [[ -d "$file" ]]; then
                            info "\t- $(basename "$file")"
                        else
                            info "\t- $(basename "$file")"
                        fi
                    done
                else
                    debug "It wasn't a dir either, looks like the user just wanted to run the wrapper. Maybe they want to update only?"
                    success "We're done here."
                fi
            else
                script=${@:1:cmdEndIndex-1}
                script="${script// //}.sh"
                # Prefer subfolder script when both name.sh and name/ exist and user passed a subcommand (e.g. mtx compile vite → compile/vite.sh)
                if [ $cmdEndIndex -le $# ]; then
                    nextArg="${!cmdEndIndex}"
                    baseScript="${script%.sh}"
                    if [ -f "$baseScript/$nextArg.sh" ]; then
                        script="$baseScript/$nextArg.sh"
                        ((cmdEndIndex++)) || true
                    fi
                fi
            fi
            if [ -f "$script" ]; then
                debug "Running $script"
                git -C "$scriptDir" reset --hard origin/main
                chmod +x "$script"
                args=""
                if [ $cmdEndIndex -le $# ]; then
                    for a in "${@:cmdEndIndex}"; do
                        args="$args $a"
                    done
                fi

                if [ ! -z "$hoist_target" ]; then
                    #Un-comment to disable multi-hoisting
                    # if isScriptInstalled "$hoist_target"; then
                    #     error "Error: $hoist_target is already hoisted"
                    #     exit 5
                    # fi
                    debug "Hoisting script as $hoist_target..."
                    if command -v sudo &>/dev/null; then
                        sudo ln -sf "$scriptDir/$script" "$binDir/$hoist_target"
                        sudo chmod +x "$binDir/$hoist_target"
                    else
                        ln -sf "$scriptDir/$script" "$binDir/$hoist_target"
                        chmod +x "$binDir/$hoist_target"
                    fi
                    echo "$hoist_target" >> "$packageListFile"
                    success "Hoisted $script as $hoist_target"
                    exit 0
                fi

                if [ $submerge -eq 1 ]; then
                    debug "Submerging all hoisted instances of $script..."
                    script_path="$scriptDir/$script"
                    while read -r alias; do
                        if [ "$(readlink -f "$binDir/$alias")" = "$(readlink -f "$script_path")" ]; then
                            if command -v sudo &>/dev/null; then
                                sudo rm -f "$binDir/$alias"
                            else
                                rm -f "$binDir/$alias"
                            fi
                            sed -i "/^$alias$/d" "$packageListFile"
                            success "Removed hoisted instance: $alias"
                        fi
                    done < "$packageListFile"
                    success "All hoisted instances of $script have been removed"
                    exit 0
                fi

                cd "$execDir"
                [ $verbose -ge 2 ] && echo "$args"
                export MTX_SKIP_UPDATE=1
                export MTX_VERBOSE=$verbose
                if [ $verbose -eq 1 ]; then
                    ( source "$scriptDir/$script" $args ) 1>/dev/null
                    exit $?
                elif [ $verbose -eq 4 ]; then
                    ( set -x; source "$scriptDir/$script" $args )
                    exit $?
                fi
                source "$scriptDir/$script" $args
            else
                if [ ! -z "$hoist_target" ]; then
                    error "Error: Script $script not found"
                    exit 4
                fi
            fi
        fi


esac
