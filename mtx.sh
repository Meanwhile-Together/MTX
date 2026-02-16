#!/bin/bash
## Begin Config Section (use ./reconfigure.sh to change these interactively)
gitUsername=""
gitToken=""
domain="https://github.com"
displayName="MTX"
slugName=$(echo "$displayName" | awk '{print tolower($0)}')
repo="Meanwhile-Together/MTX"
installedName="$slugName"
# macOS SIP protects /usr/bin; use /usr/local/bin (not protected)
[ "$(uname -s)" = "Darwin" ] && binDir="/usr/local/bin" || binDir="/usr/bin"
scriptDir="/etc/$slugName"
packageListFile="$scriptDir/.installed_packages"
wrapperName="mtx.sh"
# System folders: omitted from help and not treated as commands (e.g. mtx precond does nothing)
systemFolders="includes precond"
## End Config Section. Don't edit below, unless you intend to change functionality.

        is_system_folder() {
            local n="$1"
            case " $systemFolders " in *" $n "*) return 0;; *) return 1;; esac
        }

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
# 4: Script not found for installation (hoist)
# 5: Script already installed
# 6: Script not in package list for uninstallation
# 7: Wrapper script missing after clone/update
# 8: Failed to create symlink in binDir

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

        # Opt-in: script sets nobanner=1 in first 30 lines → skip 24h banner for that run only (so interactive runs don't show banner; it shows on a later run)
        get_nobanner() {
            local f="$1"
            [ -f "$f" ] || return 1
            head -30 "$f" 2>/dev/null | grep -qE '^(nobanner|no_banner)=1' || return 1
        }

        # Preload includes (bolors etc.). When running installer from repo (dir != binDir), use local includes.
        # Otherwise use installed copy so mtx help etc. use the installed bolors.
        if [ "$dir" != "$binDir" ] && [ -d "$dir/includes" ]; then
            for file in "$dir/includes"/*.sh; do
                [ -f "$file" ] && source "$file"
            done
        elif [ -d "$scriptDir/includes" ]; then
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
                if [ "$v" -le 1 ]; then
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

        # Create package list file if it doesn't exist (scriptDir must exist and be writable)
        if [ -d "$scriptDir" ] && [ -w "$scriptDir" ] && [ ! -f "$packageListFile" ]; then
            touch "$packageListFile"
        fi

        # Verbosity: 1=normal (script/precond output shown), 2=detail, 3=full, 4=trace
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
            grep -qE "^$script_name( |$)" "$packageListFile"
            return $?
        }

        print_banner() {
            local sha
            sha=$(git -C "$scriptDir" rev-parse --short HEAD 2>/dev/null || true)
            echo "o        .         o             o          ."
            echo "   ███╗   ███╗     ████████╗    ██╗  ██╗     .         o"
            echo "  ████╗ ████║ ===  ╚══██╔══╝ === ╚██╗██╔╝  .   o     ."
            echo " ██╔████╔██║   ==     ██║    ==   ╚███╔╝     ( ( O ) )"
            echo "██║╚██╔╝██║  =  °     ██║   =      ██╔██╗   o   .   °"
            echo "██║ ╚═╝ ██║      .    ██║      .  ██╔╝ ██╗      O"
            echo "██║     ██║  o        ██║    o    ╚═╝  ╚═╝  .      ."
            echo "╚═╝     ╚═╝           ╚═╝           ${sha:-}    °    o"
            echo ""
            echo "   » » » »  Z O O O O O M  » » » »   ( ( o ) )"
        }

        # Show banner at most once per 24h (stamp in user cache). Skip if script has nobanner (interactive) so banner waits for another run.
        show_banner_if_24h() {
            local script_path="${1:-}"
            [ -n "$script_path" ] && get_nobanner "$script_path" && return 0
            local stamp_dir stamp_file
            stamp_dir="${XDG_CACHE_HOME:-$HOME/.cache}/mtx"
            stamp_file="$stamp_dir/.banner_stamp"
            mkdir -p "$stamp_dir" 2>/dev/null || return 0
            if [ -f "$stamp_file" ]; then
                local now last
                now=$(date +%s)
                last=$(stat -c %Y "$stamp_file" 2>/dev/null || stat -f %m "$stamp_file" 2>/dev/null || echo "0")
                [ $((now - last)) -lt 86400 ] && return 0
            fi
            print_banner
            touch "$stamp_file" 2>/dev/null || true
        }

case "$1" in
    "banner")
        print_banner
        exit 0
        ;;
    "help")
        print_banner
        echo ""
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
                [ "$base" = "mtx.sh" ] || is_system_folder "$base" || [[ "$base" == .* ]] && continue
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
        echo "   --banner Display banner and exit"
        echo "   --version Print nnw version"
        echo "   -v       Normal: echo/echoc from scripts and preconds always print; only mtx_run subprocesses quiet (default)"
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
            "--banner")
                print_banner
                exit 0
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
            # Use id -gn for group: macOS primary group is "staff", not $USER
            ug="$USER:$(id -gn 2>/dev/null || echo staff)"
            if command -v sudo &>/dev/null; then
                sudo rm -rf "$scriptDir"
                sudo mkdir -p "$scriptDir"
                sudo chown "$ug" "$scriptDir"
            else
                rm -rf "$scriptDir"
                mkdir -p "$scriptDir"
                chown "$ug" "$scriptDir"
            fi
            updateCheck
            touch "$packageListFile" 2>/dev/null || true
            if [ ! -f "$scriptDir/$wrapperName" ]; then
                error "Install failed: $wrapperName not found in $scriptDir"
                exit 7
            fi
            if command -v sudo &>/dev/null; then
                sudo mkdir -p "$binDir" || { error "Could not create $binDir. Run: sudo mkdir -p $binDir"; exit 8; }
                [ -d "$binDir" ] || { error "Directory $binDir does not exist after mkdir"; exit 8; }
                sudo rm -f "$binDir/$installedName"
                sudo ln -sf "$scriptDir/$wrapperName" "$binDir/$installedName" || { error "Failed to create symlink. Try running the script with sudo."; exit 8; }
                sudo chmod +x "$scriptDir/$wrapperName"
            else
                mkdir -p "$binDir"
                rm -f "$binDir/$installedName"
                ln -sf "$scriptDir/$wrapperName" "$binDir/$installedName" || { error "Failed to create symlink in $binDir"; exit 8; }
                chmod +x "$scriptDir/$wrapperName"
            fi
            success "$displayName installed successfully"
            success "  Command:  $(color yellow "$installedName")"
            success "  Location: $binDir/$installedName"
            success "  Source:   $domain/$repo"
            success "  Next:     $(color green "$installedName help")"
        }

        updateCheck() {
            info "Checking for updates..."
            if [ ! -d "$scriptDir" ]; then
                error "Directory '$scriptDir' does not exist"
                exit 2
            fi

            # git remote update = fetch from remote, update local refs (nothing is pushed)
            if git -C "$scriptDir" remote update &>/dev/null; then
                if ! git -C "$scriptDir" diff --ignore-space-at-eol --quiet origin/main; then
                    info "New changes on remote; pulling..."
                    shaBefore=$(git -C "$scriptDir" rev-parse HEAD)
                    info "Pre-update SHA: $(color yellow "$shaBefore")"
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
                    success "Pulled latest from remote."
                    shaNow=$(git -C "$scriptDir" rev-parse HEAD)
                    info "Post update SHA: $(color yellow "$shaNow")"
                    if [ -n "$shaBefore" ] && [ "$shaBefore" != "$shaNow" ]; then
                        info "Commits in this update:"
                        git -C "$scriptDir" log --oneline "$shaBefore..$shaNow" 2>/dev/null | sed 's/^/  /' || true
                    fi
                    print_banner
                else
                    success "Already up to date."
                fi
            else
                if [ ! -d "$scriptDir/.git" ]; then
                    info "Cloning repository..."
                else
                    error "Could not fetch from remote. Recloning..."
                fi
                if ! git clone --depth 1 "$domain/$repo" "$scriptDir"; then
                    error "Failed to clone repository. Check permissions and network."
                    exit 3
                fi
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
                if [ -d "$pathSoFar" ] && ! is_system_folder "$w"; then
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

            # Strip --hoist=* and --submerge from anywhere in args so they work after script path (e.g. mtx project menu --hoist=myalias)
            SCRIPT_ARGS=()
            for a in "$@"; do
                case "$a" in
                    --hoist=*) hoist_target="${a#*=}"; debug "Hoist flag detected, will hoist script as $hoist_target" ;;
                    --submerge) submerge=1; debug "Submerge flag detected, will remove all hoisted instances of current script" ;;
                    *) SCRIPT_ARGS+=("$a") ;;
                esac
            done

            cmdEndIndex=$(isolateScript "${SCRIPT_ARGS[@]}")
            debug "cmdEndIndex: $cmdEndIndex"
            if [ $((cmdEndIndex - 1)) -lt 0 ]; then
                debug "Wasn't a script, lets see if its a dir."
                cmdEndIndex=$(isolateDir "${SCRIPT_ARGS[@]}")
                if [ $((cmdEndIndex - 1)) -gt 0 ]; then
                    debug "It was a dir! Lets list the contents for the user."
                    script=$(IFS=/; echo "${SCRIPT_ARGS[*]:0:cmdEndIndex-1}")
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
                script=$(IFS=/; echo "${SCRIPT_ARGS[*]:0:cmdEndIndex-1}.sh")
                # Prefer subfolder script when both name.sh and name/ exist and user passed a subcommand (e.g. mtx compile vite → compile/vite.sh)
                if [ $cmdEndIndex -le ${#SCRIPT_ARGS[@]} ]; then
                    nextArg="${SCRIPT_ARGS[cmdEndIndex-1]}"
                    baseScript="${script%.sh}"
                    if [ -f "$baseScript/$nextArg.sh" ]; then
                        script="$baseScript/$nextArg.sh"
                        ((cmdEndIndex++)) || true
                    fi
                fi
            fi
            if [ -f "$script" ]; then
                show_banner_if_24h "$scriptDir/$script"
                debug "Running $script"
                git -C "$scriptDir" reset --hard origin/main
                chmod +x "$script"
                args=""
                if [ $cmdEndIndex -le ${#SCRIPT_ARGS[@]} ]; then
                    for a in "${SCRIPT_ARGS[@]:cmdEndIndex-1}"; do
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
                    # Wrapper script so hoisted command runs via mtx (execDir, preconds, same context as "mtx <path>")
                    script_words="${script%.sh}"
                    script_words="${script_words//\// }"
                    wrapper_content="#!/bin/bash
# mtx-hoist: $script
exec $installedName $script_words \"\$@\"
"
                    if command -v sudo &>/dev/null; then
                        echo "$wrapper_content" | sudo tee "$binDir/$hoist_target" >/dev/null
                        sudo chmod +x "$binDir/$hoist_target"
                    else
                        echo "$wrapper_content" > "$binDir/$hoist_target"
                        chmod +x "$binDir/$hoist_target"
                    fi
                    echo "$hoist_target $script" >> "$packageListFile"
                    success "Hoisted $script as $hoist_target"
                    exit 0
                fi

                if [ $submerge -eq 1 ]; then
                    debug "Submerging all hoisted instances of $script..."
                    script_path="$scriptDir/$script"
                    while IFS= read -r line; do
                        alias="${line%% *}"
                        installed_script="${line#* }"
                        installed_script="${installed_script%% *}"
                        [ -n "$alias" ] || continue
                        if [ -z "$installed_script" ]; then
                            # Old format: one word per line; check symlink target (readlink -f is GNU-only; skip check on macOS/BSD)
                            target=$(readlink -f "$binDir/$alias" 2>/dev/null)
                            script_canon=$(readlink -f "$script_path" 2>/dev/null)
                            [ -z "$target" ] || [ -z "$script_canon" ] || [ "$target" != "$script_canon" ] && continue
                        else
                            [ "$installed_script" = "$script" ] || continue
                        fi
                        if command -v sudo &>/dev/null; then
                            sudo rm -f "$binDir/$alias"
                        else
                            rm -f "$binDir/$alias"
                        fi
                        if [ -z "$installed_script" ]; then
                            grep -v -F -x "$alias" "$packageListFile" > "$packageListFile.tmp" && mv "$packageListFile.tmp" "$packageListFile"
                        else
                            grep -v -F -x "$alias $script" "$packageListFile" > "$packageListFile.tmp" && mv "$packageListFile.tmp" "$packageListFile"
                        fi
                        success "Removed hoisted instance: $alias"
                    done < "$packageListFile"
                    success "All hoisted instances of $script have been removed"
                    exit 0
                fi

                cd "$execDir"
                if [ -d "$scriptDir/precond" ] && [ "$script" != "workspace.sh" ]; then
                    for pre in "$scriptDir"/precond/*.sh; do
                        [ -f "$pre" ] || continue
                        source "$pre" || { r=$?; exit $r; }
                    done
                fi
                [ $verbose -ge 2 ] && echo "$args"
                export MTX_SKIP_UPDATE=1
                export MTX_VERBOSE=$verbose
                if [ $verbose -eq 4 ]; then
                    ( set -x; source "$scriptDir/$script" $args )
                    exit $?
                fi
                # Script/precond stdout always shown (echo, echoc, etc.). Only mtx_run subprocesses are quiet at default.
                source "$scriptDir/$script" $args
            else
                if [ ! -z "$hoist_target" ]; then
                    error "Error: Script $script not found"
                    exit 4
                fi
            fi
        fi


esac
