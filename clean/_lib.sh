#!/usr/bin/env bash
# Shared implementation for mtx clean / mtx sys clean / clean/<scope>.sh
# shellcheck disable=SC2034  # colors used with echo -e at call sites

mtx_clean_color_setup() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
}

mtx_clean_usage() {
    echo "Usage: mtx clean [payload|org|all] [--scope=payload|org|all] [--yes]"
    echo "       mtx sys clean …   (same behavior, legacy path)"
    echo ""
    echo "  With no scope: auto-detect from cwd (after precond):"
    echo "    • Under an org host's payloads/…  → payload (this package only)."
    echo "    • Else under an org host (payloads/ at repo root) → org (host + all payloads/*)."
    echo "    • Else → payload (walks to config/app.json root when present, else cwd)."
    echo ""
    echo "  all  Every package.json tree under MTX_WORKSPACE_ROOT (from precond), or workspace"
    echo "       detected from cwd, else git toplevel / cwd."
    echo ""
    echo "  --yes / MTX_CLEAN_YES=1  Skip the final confirmation prompt."
    echo "  MTX_CLEAN_SCOPE=payload|org|all  Non-interactive default scope."
}

# First directory up from $1 containing payloads/ with at least one child dir.
mtx_clean_find_org_root() {
    local walk="${1:-$(pwd)}"
    walk="$(cd "$walk" && pwd)"
    while [ -n "$walk" ] && [ "$walk" != "/" ]; do
        if [ -d "$walk/payloads" ]; then
            local any=""
            any="$(find "$walk/payloads" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
            if [ -n "$any" ]; then
                printf '%s' "$walk"
                return 0
            fi
        fi
        walk="$(dirname "$walk")"
    done
    return 1
}

mtx_clean_path_under_org_payloads() {
    local here oroot
    here="$(cd "${1:-$(pwd)}" && pwd)"
    oroot="$(cd "$2" && pwd)"
    case "$here" in
        "$oroot"/payloads | "$oroot"/payloads/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Walk from cwd for config/app.json (same idea as prepare.sh).
mtx_clean_resolve_project_root() {
    local start="${1:-$(pwd)}"
    local walk
    walk="$(cd "$start" && pwd)"
    if [ -f "$walk/config/app.json" ]; then
        printf '%s' "$walk"
        return 0
    fi
    if [ -f "$walk/../config/app.json" ]; then
        (cd "$walk/.." && pwd)
        return 0
    fi
    local d
    for d in . .. "../project-bridge"; do
        if [ -f "$walk/$d/config/app.json" ]; then
            (cd "$walk/$d" && pwd)
            return 0
        fi
    done
    printf '%s' "$walk"
}

mtx_clean_all_scan_root() {
    # Prefer MTX_WORKSPACE_ROOT from precond (multi-repo), else detect workspace, else git/pwd.
    local start="${1:-$(pwd)}"
    if [ -n "${MTX_WORKSPACE_ROOT:-}" ] && [ -d "$MTX_WORKSPACE_ROOT" ]; then
        printf '%s' "$(cd "$MTX_WORKSPACE_ROOT" && pwd)"
        return 0
    fi
    local _mtx_root
    _mtx_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
    if [ -f "$_mtx_root/includes/prepare-env.sh" ]; then
        # shellcheck source=../includes/prepare-env.sh
        source "$_mtx_root/includes/prepare-env.sh" 2>/dev/null || true
    fi
    if type mtx_detect_workspace_root &>/dev/null; then
        local w
        if w="$(mtx_detect_workspace_root "$start" 2>/dev/null)" && [ -n "$w" ] && [ -d "$w" ]; then
            printf '%s' "$(cd "$w" && pwd)"
            return 0
        fi
    fi
    local g
    g="$(cd "$start" && git rev-parse --show-toplevel 2>/dev/null)" || true
    if [ -n "$g" ] && [ -d "$g" ]; then
        printf '%s' "$(cd "$g" && pwd)"
        return 0
    fi
    printf '%s' "$(cd "$start" && pwd)"
}

mtx_clean_parse_args() {
    CLEAN_SCOPE="${MTX_CLEAN_SCOPE:-}"
    MTX_CLEAN_YES="${MTX_CLEAN_YES:-}"
    local a
    for a in "$@"; do
        case "$a" in
            --scope=payload | --scope=org | --scope=all)
                CLEAN_SCOPE="${a#--scope=}"
                ;;
            --scope=*)
                echo -e "${RED}Invalid --scope= (use payload, org, or all).${NC}" >&2
                exit 1
                ;;
            --yes | -y)
                MTX_CLEAN_YES=1
                ;;
            -h | --help)
                mtx_clean_usage
                exit 0
                ;;
            payload | org | all)
                CLEAN_SCOPE="$a"
                ;;
            *)
                echo -e "${RED}Unknown argument: $a${NC}" >&2
                mtx_clean_usage >&2
                exit 1
                ;;
        esac
    done
}

mtx_clean_autodetect() {
    CLEAN_AUTO_MSG=""
    unset MTX_CLEAN_ORG_ROOT MTX_CLEAN_SINGLE_ROOT MTX_CLEAN_ALL_SCAN_ROOT 2>/dev/null || true
    local here oroot
    here="$(cd "$(pwd)" && pwd)"
    if oroot="$(mtx_clean_find_org_root "$here")"; then
        oroot="$(cd "$oroot" && pwd)"
        if mtx_clean_path_under_org_payloads "$here" "$oroot"; then
            CLEAN_SCOPE="payload"
            CLEAN_AUTO_MSG="Auto: payload under org at ${oroot} — cleaning this package only (${here})."
            MTX_CLEAN_ORG_ROOT="$oroot"
            MTX_CLEAN_SINGLE_ROOT="$here"
            return 0
        fi
        CLEAN_SCOPE="org"
        CLEAN_AUTO_MSG="Auto: org host at ${oroot} — cleaning org root and payloads/*."
        MTX_CLEAN_ORG_ROOT="$oroot"
        return 0
    fi
    CLEAN_SCOPE="payload"
    local root
    root="$(mtx_clean_resolve_project_root "$here")"
    MTX_CLEAN_SINGLE_ROOT="$root"
    CLEAN_AUTO_MSG="Auto: payload project at ${root}."
}

mtx_clean_collect_roots() {
    local here root d dir scan_root oroot
    here="$(cd "$(pwd)" && pwd)"
    CLEAN_ROOTS=()

    case "$CLEAN_SCOPE" in
        payload)
            if [ -n "${MTX_CLEAN_SINGLE_ROOT:-}" ]; then
                CLEAN_ROOTS+=("$(cd "$MTX_CLEAN_SINGLE_ROOT" && pwd)")
            else
                CLEAN_ROOTS+=("$here")
            fi
            ;;
        org)
            oroot="${MTX_CLEAN_ORG_ROOT:-}"
            if [ -z "$oroot" ]; then
                oroot="$(mtx_clean_find_org_root "$here" || true)"
            fi
            if [ -z "$oroot" ]; then
                echo -e "${RED}Org scope requires an org host (directory with payloads/*/ ).${NC}" >&2
                exit 1
            fi
            oroot="$(cd "$oroot" && pwd)"
            CLEAN_ROOTS+=("$oroot")
            if [ -d "$oroot/payloads" ]; then
                for d in "$oroot"/payloads/*/; do
                    [ -d "$d" ] || continue
                    CLEAN_ROOTS+=("$(cd "$d" && pwd)")
                done
            fi
            ;;
        all)
            scan_root="$(mtx_clean_all_scan_root "$here")"
            scan_root="$(cd "$scan_root" && pwd)"
            MTX_CLEAN_ALL_SCAN_ROOT="$scan_root"
            while IFS= read -r -d '' pkg; do
                dir="$(cd "$(dirname "$pkg")" && pwd)"
                CLEAN_ROOTS+=("$dir")
            done < <(
                find "$scan_root" \( -path "$scan_root/.git" -o -path "$scan_root/.git/*" \) -prune -o \
                    \( ! -path "*/node_modules/*" -type f -name package.json -print0 \) 2>/dev/null | sort -zu
            )
            ;;
    esac
}

mtx_clean_dedupe_roots_sorted() {
    local r seen="|"
    local -a uniq=()
    for r in "${CLEAN_ROOTS[@]}"; do
        [ -n "$r" ] || continue
        case "$seen" in
            *"|$r|"*) continue ;;
        esac
        seen="${seen}${r}|"
        uniq+=("$r")
    done
    if [ ${#uniq[@]} -eq 0 ]; then
        CLEAN_ROOTS=()
        return 0
    fi
    mapfile -t CLEAN_ROOTS < <(printf '%s\n' "${uniq[@]}" | LC_ALL=C sort -u)
}

mtx_clean_remove_dir() {
    local dir="$1"
    local desc="$2"
    if [ -d "$dir" ]; then
        local size
        size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
        echo -e "${YELLOW}Removing $desc...${NC} ($size)"
        rm -rf "$dir"
        echo -e "${GREEN}✅ Removed $desc${NC}"
    else
        echo -e "${BLUE}⏭️  Skipping $desc (not found)${NC}"
    fi
}

mtx_clean_remove_file() {
    local file="$1"
    local desc="$2"
    if [ -f "$file" ]; then
        local size
        size=$(du -h "$file" 2>/dev/null | awk '{print $1}')
        echo -e "${YELLOW}Removing $desc...${NC} ($size)"
        rm -f "$file"
        echo -e "${GREEN}✅ Removed $desc${NC}"
    else
        echo -e "${BLUE}⏭️  Skipping $desc (not found)${NC}"
    fi
}

mtx_clean_artifacts_at() {
    local BASE="$1"
    BASE="${BASE%/}"
    if [ ! -d "$BASE" ]; then
        echo -e "${YELLOW}Skipping missing directory: $BASE${NC}"
        return 0
    fi

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📁 Cleaning:${NC} ${YELLOW}$BASE${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    (
        cd "$BASE" || exit 1

        echo -e "${BLUE}━━━ Desktop Build Artifacts ━━━${NC}"
        mtx_clean_remove_dir "targets/desktop/release" "Desktop release builds"
        mtx_clean_remove_dir "targets/desktop/dist" "Desktop dist folder"
        mtx_clean_remove_dir "targets/desktop/build" "Desktop build folder"

        echo ""
        echo -e "${BLUE}━━━ Mobile Build Artifacts ━━━${NC}"
        mtx_clean_remove_dir "targets/mobile/android/app/build" "Android app build artifacts"
        mtx_clean_remove_dir "targets/mobile/android/.gradle" "Android Gradle cache"
        mtx_clean_remove_dir "targets/mobile/android/build" "Android build folder"
        mtx_clean_remove_dir "targets/mobile/ios/build" "iOS build folder"
        mtx_clean_remove_dir "targets/mobile/dist" "Mobile dist folder"

        echo ""
        echo -e "${BLUE}━━━ Server Build Artifacts ━━━${NC}"
        mtx_clean_remove_dir "targets/server/dist" "Server dist folder"
        mtx_clean_remove_dir "targets/server/src/db/generated" "Prisma generated files (will be regenerated on next build)"

        echo ""
        echo -e "${BLUE}━━━ Client Build Artifacts ━━━${NC}"
        mtx_clean_remove_dir "targets/client/dist" "Client dist folder"
        mtx_clean_remove_dir "targets/client/build" "Client build folder"

        echo ""
        echo -e "${BLUE}━━━ Backend Build Artifacts ━━━${NC}"
        mtx_clean_remove_dir "targets/backend/dist" "Backend dist folder"
        mtx_clean_remove_dir "targets/backend/build" "Backend build folder"
        mtx_clean_remove_dir "targets/backend-server/dist" "Backend-server dist folder"

        echo ""
        echo -e "${BLUE}━━━ Root Build Artifacts ━━━${NC}"
        mtx_clean_remove_dir "dist" "Root dist folder"

        echo ""
        echo -e "${BLUE}━━━ Terraform Artifacts ━━━${NC}"
        mtx_clean_remove_dir "terraform/.terraform" "Terraform provider binaries"
        mtx_clean_remove_file "terraform/terraform.tfstate" "Terraform state file"
        mtx_clean_remove_file "terraform/terraform.tfstate.backup" "Terraform state backup"
        mtx_clean_remove_file "terraform/tfplan" "Terraform plan file"
        mtx_clean_remove_file "terraform/.terraform.lock.hcl" "Terraform lock file"

        echo ""
        echo -e "${BLUE}━━━ Other Generated Files ━━━${NC}"
        mtx_clean_remove_dir ".railway" "Railway local config (will be recreated on next deploy)"
        mtx_clean_remove_dir ".cursor" "Cursor cache"

        echo ""
        echo -e "${BLUE}━━━ Package Build Artifacts ━━━${NC}"
        mtx_clean_remove_dir "application/dist" "Application dist folder"
        mtx_clean_remove_dir "application/build" "Application build folder"
        mtx_clean_remove_dir "shared/dist" "Shared dist folder"
        mtx_clean_remove_dir "shared/build" "Shared build folder"
        mtx_clean_remove_dir "engine/dist" "Engine dist folder"
        mtx_clean_remove_dir "engine/build" "Engine build folder"
    )
}

# Entry: optional MTX_CLEAN_NO_AUTO=1 (from clean/payload.sh etc.) skips autodetect.
mtx_clean_entry() {
    mtx_clean_color_setup
    mtx_clean_parse_args "$@"

    if [ -n "${MTX_CLEAN_NO_AUTO:-}" ]; then
        : "${CLEAN_SCOPE:?MTX_CLEAN_NO_AUTO requires scope}"
    elif [ -z "$CLEAN_SCOPE" ]; then
        mtx_clean_autodetect
    else
        unset MTX_CLEAN_ORG_ROOT MTX_CLEAN_SINGLE_ROOT MTX_CLEAN_ALL_SCAN_ROOT CLEAN_AUTO_MSG 2>/dev/null || true
    fi

    case "${CLEAN_SCOPE:-}" in
        payload | org | all) ;;
        *)
            echo -e "${RED}Invalid scope (use payload, org, or all).${NC}" >&2
            exit 1
            ;;
    esac

    echo -e "${BLUE}🧹 Project clean${NC}"
    echo -e "Scope: ${YELLOW}$CLEAN_SCOPE${NC}"
    if [ -n "${CLEAN_AUTO_MSG:-}" ]; then
        echo -e "${GREEN}$CLEAN_AUTO_MSG${NC}"
    fi
    echo "This will remove build artifacts and generated files under each target root."
    echo ""

    CLEAN_ROOTS=()
    mtx_clean_collect_roots
    mtx_clean_dedupe_roots_sorted

    if [ "$CLEAN_SCOPE" = "all" ] && [ -n "${MTX_CLEAN_ALL_SCAN_ROOT:-}" ]; then
        echo -e "${GREEN}All: scanning workspace/tree at ${MTX_CLEAN_ALL_SCAN_ROOT}${NC}"
        echo ""
    fi

    if [ ${#CLEAN_ROOTS[@]} -eq 0 ]; then
        echo -e "${YELLOW}No directories to clean.${NC}"
        exit 0
    fi

    echo -e "${BLUE}Target roots (${#CLEAN_ROOTS[@]}):${NC}"
    for r in "${CLEAN_ROOTS[@]}"; do
        echo "  - $r"
    done
    echo ""

    if [ ${#CLEAN_ROOTS[@]} -eq 1 ]; then
        echo -e "${BLUE}📊 Calculating current size...${NC}"
        BEFORE_SIZE=$(du -sh --exclude=node_modules --exclude=.git "${CLEAN_ROOTS[0]}" 2>/dev/null | awk '{print $1}')
        echo -e "Size before (excluding node_modules): ${YELLOW}$BEFORE_SIZE${NC}"
        echo ""
    fi

    if [ "${MTX_CLEAN_YES:-}" = "1" ]; then
        REPLY="y"
    else
        read -r -p "Continue with clean? (y/N): " -n 1 -r
        echo ""
    fi
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Clean cancelled.${NC}"
        exit 0
    fi

    echo ""
    echo -e "${BLUE}🗑️  Starting clean...${NC}"

    local r
    for r in "${CLEAN_ROOTS[@]}"; do
        mtx_clean_artifacts_at "$r"
    done

    echo ""
    echo -e "${BLUE}━━━ Clean Summary ━━━${NC}"
    if [ ${#CLEAN_ROOTS[@]} -eq 1 ]; then
        AFTER_SIZE=$(du -sh --exclude=node_modules --exclude=.git "${CLEAN_ROOTS[0]}" 2>/dev/null | awk '{print $1}')
        echo -e "Size before: ${YELLOW}$BEFORE_SIZE${NC}"
        echo -e "Size after:  ${GREEN}$AFTER_SIZE${NC}"
    else
        echo -e "Cleaned ${GREEN}${#CLEAN_ROOTS[@]}${NC} roots (per-root size skipped)."
    fi
    echo ""

    echo -e "${GREEN}✅ Clean complete!${NC}"
    echo ""
    echo -e "${BLUE}💡 Note:${NC}"
    echo "  - Prisma generated files will be regenerated on next 'npm run build:server'"
    echo "  - Terraform providers will be downloaded on next 'terraform init'"
    echo "  - Build artifacts will be regenerated on next build"
    echo "  - Railway local config will be recreated on next deploy"
    echo ""
}
