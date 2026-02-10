#!/bin/bash
# MTX test deploy-config: test deploy.json platform array parsing (from shell-scripts.md §13)
desc="Test deploy.json platform array parsing"
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TEST_DIR=$(mktemp -d)
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

test_platform_parsing() {
    local test_name="$1"
    local deploy_json="$2"
    local expected_platform="$3"

    TEST_COUNT=$((TEST_COUNT + 1))

    echo "$deploy_json" > "$TEST_DIR/deploy.json"

    PLATFORM_TYPE=$(jq -r '.platform | type' "$TEST_DIR/deploy.json" 2>/dev/null || echo "string")

    if [ "$PLATFORM_TYPE" = "array" ]; then
        DEPLOYMENT_PLATFORM=$(jq -r '.platform[] | select(. == "railway" or . == "vercel") | .' "$TEST_DIR/deploy.json" | head -n1)
    else
        DEPLOYMENT_PLATFORM=$(jq -r '.platform // ""' "$TEST_DIR/deploy.json" 2>/dev/null || echo "")
    fi

    if [ -z "$DEPLOYMENT_PLATFORM" ]; then
        DEPLOYMENT_PLATFORM=""
    fi

    if [ "$DEPLOYMENT_PLATFORM" = "$expected_platform" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected platform: $expected_platform, got: $DEPLOYMENT_PLATFORM"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

echo "Running deploy.json platform array parsing tests..."
echo ""

test_platform_parsing \
    "Array format: [\"railway\"]" \
    '{"platform": ["railway"], "projectId": ""}' \
    "railway"

test_platform_parsing \
    "Array format: [\"railway\", \"other\"]" \
    '{"platform": ["railway", "other"], "projectId": ""}' \
    "railway"

test_platform_parsing \
    "Array format: [\"vercel\"]" \
    '{"platform": ["vercel"], "projectId": ""}' \
    "vercel"

TEST_COUNT=$((TEST_COUNT + 1))
echo '{"platform": "railway", "projectId": ""}' > "$TEST_DIR/deploy.json"
PLATFORM_TYPE=$(jq -r '.platform | type' "$TEST_DIR/deploy.json" 2>/dev/null || echo "null")
if [ "$PLATFORM_TYPE" != "array" ]; then
    echo -e "${GREEN}✓${NC} String format: \"railway\" (correctly rejected - not an array)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗${NC} String format: \"railway\" (incorrectly accepted as array)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

test_platform_parsing \
    "Array format: []" \
    '{"platform": [], "projectId": ""}' \
    ""

test_platform_parsing \
    "Array format: [\"railway\", \"vercel\"]" \
    '{"platform": ["railway", "vercel"], "projectId": ""}' \
    "railway"

echo ""
echo "Test Results:"
echo "  Total: $TEST_COUNT"
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
