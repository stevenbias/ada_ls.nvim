#!/bin/bash
# Comprehensive test runner with optional dependency installation and auto-cleanup
# 
# This script:
# 1. Creates isolated .busted-test-env/ directory for test dependencies
# 2. Attempts to install telescope.nvim and neo-tree.nvim (30 sec timeout each)
# 3. Runs busted tests (Tier 1 + Tier 2 if deps available)
# 4. Generates coverage report
# 5. Verifies coverage meets 85% threshold
# 6. Auto-cleans up .busted-test-env/ on exit (success or failure)
#
# Environment isolation ensures:
# - Zero pollution to project structure
# - Each test run gets fresh dependencies
# - CI can safely rebuild from scratch each time

set -e  # Exit on any error

PROJECT_ROOT="${PWD}"
TEST_ENV_DIR="${PROJECT_ROOT}/.busted-test-env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to cleanup on exit (success or failure)
cleanup() {
  local exit_code=$?
  echo ""
  echo -e "${BLUE}=== Cleanup ===${NC}"
  echo "Removing isolated test environment: ${TEST_ENV_DIR}"
  rm -rf "${TEST_ENV_DIR}"
  echo -e "${GREEN}✓ Cleanup complete${NC}"
  exit $exit_code
}

# Register cleanup to run on any exit (success, failure, or signal)
trap cleanup EXIT

echo -e "${BLUE}=== Ada_ls.nvim Comprehensive Test Suite ===${NC}"
echo ""

# Detect Neovim version for compatibility reporting
NEOVIM_VERSION="${NEOVIM_VERSION:-}"
if [ -z "$NEOVIM_VERSION" ]; then
  NEOVIM_VERSION=$(nvim --version | head -n 1 | grep -oP 'NVIM v\K[^\s]+' || echo "unknown")
fi
echo "Testing with Neovim: $NEOVIM_VERSION"
echo ""

# Detect Neovim's built-in module path for luv (early, before subshells)
NEOVIM_CPATH=""
NLUA_PATH=$(which nlua 2>/dev/null || echo "")
if [ -n "$NLUA_PATH" ]; then
  NEOVIM_CPATH=$("$NLUA_PATH" -e "local cpath = package.cpath; for p in cpath:gmatch('[^;]+') do if string.find(p, 'nvim') or string.find(p, '.deps') then io.write(p); break end end" 2>/dev/null || true)
fi
# Fallback: try common Neovim build paths if detection failed
if [ -z "$NEOVIM_CPATH" ]; then
  for common_path in "/build/nvim/parts/nvim/build/.deps/usr/lib/lua/5.1/?.so" "/usr/lib/lua/5.1/?.so"; do
    if [ -d "${common_path%/\?\.so}" ]; then
      NEOVIM_CPATH="$common_path"
      break
    fi
  done
fi
if [ -n "$NEOVIM_CPATH" ]; then
  echo "Detected Neovim module path: ${NEOVIM_CPATH}"
fi
echo ""

# Step 1: Create isolated test environment
echo -e "${BLUE}Step 1: Setting up isolated test environment${NC}"
mkdir -p "${TEST_ENV_DIR}"
echo "Created: ${TEST_ENV_DIR}"

# Step 2: Generate LuaRocks configuration for isolated tree
echo -e "${BLUE}Step 2: Generating LuaRocks configuration${NC}"
cat > "${TEST_ENV_DIR}/luarocks-config.lua" <<EOF
-- Isolated LuaRocks configuration
rocks_trees = { "${TEST_ENV_DIR}" }
EOF
echo "Generated: ${TEST_ENV_DIR}/luarocks-config.lua"

# Step 3: Verify LFS is available (required by Penlight/Busted)
echo ""
echo -e "${BLUE}Step 3: Checking dependencies${NC}"
if ! lua -e "require('lfs')" 2>/dev/null; then
  echo -e "${RED}✗ FAIL: LFS (Lua File System) is required but not installed${NC}"
  echo "Install with: sudo apt-get install lua-filesystem"
  exit 1
fi
echo -e "${GREEN}✓ LFS available${NC}"
echo ""

# Step 4: Attempt to install optional test dependencies
echo -e "${BLUE}Step 4: Installing optional test dependencies${NC}"
echo "(each has 30 second timeout, graceful fallback if unavailable)"
echo ""

TELESCOPE_AVAILABLE=false
NEO_TREE_AVAILABLE=false

# Install Plenary as dependency of Telescope
echo -n "Installing plenary.nvim... "
if timeout 30 luarocks install --tree="${TEST_ENV_DIR}" plenary.nvim >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC}"
else
  echo -e "${YELLOW}✗${NC} (non-critical)"
fi

# Install Telescope
echo -n "Installing telescope.nvim... "
if timeout 30 luarocks install --tree="${TEST_ENV_DIR}" telescope.nvim >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC}"
  TELESCOPE_AVAILABLE=true
else
  echo -e "${YELLOW}✗${NC}"
  TELESCOPE_AVAILABLE=false
fi

# Install Neo-tree
echo -n "Installing neo-tree.nvim... "
if timeout 30 luarocks install --tree="${TEST_ENV_DIR}" neo-tree.nvim >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC}"
  NEO_TREE_AVAILABLE=true
else
  echo -e "${YELLOW}✗${NC}"
  NEO_TREE_AVAILABLE=false
fi

# Install Nui as dependency of Neo-tree
echo -n "Installing nui.nvim... "
if timeout 30 luarocks install --tree="${TEST_ENV_DIR}" nui.nvim >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC}"
else
  echo -e "${YELLOW}✗${NC} (non-critical)"
fi

echo ""

# Step 5: Report what will be tested
echo -e "${BLUE}Step 5: Test configuration${NC}"
echo "Optional dependency status:"
if [ "$TELESCOPE_AVAILABLE" = true ]; then
  echo "  ✓ Telescope.nvim available (Tier 2 telescope tests will run)"
else
  echo "  ✗ Telescope.nvim unavailable (Tier 2 telescope tests will be skipped)"
fi
if [ "$NEO_TREE_AVAILABLE" = true ]; then
  echo "  ✓ Neo-tree.nvim available (Tier 2 neo-tree binary available)"
  echo "    Note: Backend tests skipped - requires vim.loop API (not available in nlua)"
else
  echo "  ✗ Neo-tree.nvim unavailable (Tier 2 neo-tree tests will be skipped)"
fi
echo ""

if [ "$TELESCOPE_AVAILABLE" = true ] || [ "$NEO_TREE_AVAILABLE" = true ]; then
  echo -e "${GREEN}Running Tier 1 + Tier 2 tests (with real dependencies)${NC}"
else
  echo -e "${YELLOW}Running Tier 1 tests only (mock-based)${NC}"
  echo "Coverage target: 85% (achievable with Tier 1 tests)"
fi

echo ""

# Step 6: Clean previous coverage data
echo -e "${BLUE}Step 6: Cleaning previous coverage data${NC}"
rm -f luacov.stats.out luacov.report.out
echo "Cleared: luacov.stats.out luacov.report.out"

# Step 7: Run tests with coverage
echo ""
echo -e "${BLUE}Step 7: Running test suite${NC}"
echo ""

# If we have dependencies, set environment for them and run tests
BUSTED_EXIT=0
BUSTED_OUTPUT=""

if [ "$TELESCOPE_AVAILABLE" = true ] || [ "$NEO_TREE_AVAILABLE" = true ]; then
  export LUAROCKS_CONFIG="${TEST_ENV_DIR}/luarocks-config.lua"
  export LUA_PATH="${TEST_ENV_DIR}/share/lua/5.1/?.lua;${TEST_ENV_DIR}/share/lua/5.1/?/init.lua;;${LUA_PATH}"
  # Add Neovim's module paths so Telescope can find luv
  if [ -n "$NEOVIM_CPATH" ]; then
    export LUA_CPATH="${TEST_ENV_DIR}/lib/lua/5.1/?.so;${NEOVIM_CPATH};/usr/local/lib/lua/5.1/?.so;${LUA_CPATH}"
  else
    export LUA_CPATH="${TEST_ENV_DIR}/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/?.so;${LUA_CPATH}"
  fi
  
  # Validate environment variables were exported correctly
  echo "Validating Lua environment paths..."
  if lua -e "package.path = os.getenv('LUA_PATH') or package.path; require('lfs'); print('✓ Lua paths validated')" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Lua environment validated${NC}"
  else
    echo -e "${YELLOW}⚠ Warning: Could not fully validate Lua environment${NC}"
  fi
  
  BUSTED_OUTPUT=$(timeout 600 bash -c 'ADA_LS_TEST_MODE=1 busted 2>&1' || BUSTED_EXIT=$?)
  echo "$BUSTED_OUTPUT"
else
  BUSTED_OUTPUT=$(timeout 600 bash -c 'ADA_LS_TEST_MODE=1 busted 2>&1' || BUSTED_EXIT=$?)
  echo "$BUSTED_OUTPUT"
fi

# Check for timeout
if [ "$BUSTED_EXIT" -eq 124 ]; then
  echo -e "${RED}✗ FAIL: Tests timed out (exceeded 600 seconds)${NC}"
  echo "Infinite loop or deadlock detected. Check recent test changes."
  exit 1
fi

# Extract test result counts from busted output
# Pattern: "X successes / Y failures / Z errors / W pending"
SUCCESSES=$(echo "$BUSTED_OUTPUT" | grep -oP '\d+(?= successes)' | tail -1)
FAILURES=$(echo "$BUSTED_OUTPUT" | grep -oP '\d+(?= failures)' | tail -1)
ERRORS=$(echo "$BUSTED_OUTPUT" | grep -oP '\d+(?= errors)' | tail -1)
PENDING=$(echo "$BUSTED_OUTPUT" | grep -oP '\d+(?= pending)' | tail -1)

# Validate extracted counts (default to 0 if not found)
SUCCESSES=${SUCCESSES:-0}
FAILURES=${FAILURES:-0}
ERRORS=${ERRORS:-0}
PENDING=${PENDING:-0}

# Generate coverage if coverage data exists (even if tests failed)
if [ -f luacov.stats.out ]; then
  # Step 8: Generate coverage report
  echo ""
  echo -e "${BLUE}Step 8: Generating coverage report${NC}"
  luacov

  # Step 9: Display coverage summary
  echo ""
  echo -e "${BLUE}=== Coverage Summary ===${NC}"
  cat luacov.report.out

  # Step 10: Verify coverage meets threshold
  echo ""
  echo -e "${BLUE}Step 10: Verifying coverage threshold${NC}"
  COVERAGE_PERCENT=$(grep "^Total" luacov.report.out | awk '{print $NF}')
  if [ -z "$COVERAGE_PERCENT" ]; then
    echo -e "${RED}✗ FAIL: Could not parse coverage percentage from luacov.report.out${NC}"
    exit 1
  fi
  if ! [[ "$COVERAGE_PERCENT" =~ ^[0-9]+(%|[.][0-9]+%)$ ]]; then
    echo -e "${RED}✗ FAIL: Invalid coverage format: $COVERAGE_PERCENT${NC}"
    exit 1
  fi
  COVERAGE_INT=$(echo "$COVERAGE_PERCENT" | sed 's/%.*//' | sed 's/\..*//')

  echo "Coverage percentage: ${COVERAGE_PERCENT}"

  if [ "$COVERAGE_INT" -lt 85 ]; then
    echo -e "${RED}✗ FAIL: Coverage ${COVERAGE_PERCENT} is below 85% threshold${NC}"
    echo "Please add more tests to improve coverage."
    exit 1
  else
    echo -e "${GREEN}✓ OK: Coverage ${COVERAGE_PERCENT} meets 85% threshold${NC}"
  fi

  echo ""
  
  # Step 11: Display final test results summary
  echo -e "${BLUE}Step 11: Test Results Summary${NC}"
  echo "$SUCCESSES successes / $FAILURES failures / $ERRORS errors / $PENDING pending"
  echo ""
  
  # Check if tests failed (failures or errors)
  if [ "$FAILURES" -gt 0 ] || [ "$ERRORS" -gt 0 ]; then
    echo -e "${RED}✗ FAIL: Tests failed (Failures: $FAILURES, Errors: $ERRORS)${NC}"
    exit 1
  else
    echo -e "${GREEN}✓ All Tests Passed${NC}"
  fi
  
  # Step 12: Skipped Tests Report
  # Report which tests are skipped and why
  echo ""
  echo -e "${BLUE}Step 12: Skipped Tests Report${NC}"
  
  # Define test counts for various scenarios
  # These constants represent the total possible tests in the codebase
  TOTAL_TESTS=518  # All tests that can run with vim.schedule mock + full environment
  
  # Calculate skipped count
  SKIPPED=$((TOTAL_TESTS - SUCCESSES))
  
  # Only report if tests are actually skipped
  if [ "$SKIPPED" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Tests skipped: $SKIPPED${NC}"
    
    # Attempt to identify which tests are skipped based on common conditions
    # Check if telescope is unavailable
    if ! grep -q "Telescope.nvim available" /tmp/test_run_output.txt 2>/dev/null; then
      echo "  - Telescope integration tests (unavailable library)"
    fi
    
    # Check if neo-tree is unavailable  
    if ! grep -q "Neo-tree.nvim available" /tmp/test_run_output.txt 2>/dev/null; then
      echo "  - Neo-tree backend tests (unavailable library)"
    fi
  else
    echo -e "${GREEN}✓ No tests skipped${NC}"
  fi
else
  echo -e "${RED}✗ FAIL: Tests did not generate coverage data${NC}"
  exit 1
fi
