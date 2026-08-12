#!/bin/bash
# Runs every automated check in the project.
#   bash run-tests.sh
set -e
cd "$(dirname "$0")"

BOLD='\033[1m'; GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
fail=0

echo -e "\n${BOLD}1/6  Release build${RESET}"
if swift build -c release 2>&1 | grep -E "error:|warning:"; then
    echo -e "  ${RED}build produced errors/warnings${RESET}"; fail=1
else
    echo -e "  ${GREEN}✓${RESET} builds clean"
fi

echo -e "\n${BOLD}2/6  Elapsed-time formatting${RESET}"
TMP=$(mktemp -d)
swiftc -O NotchSoGood/Utilities/ElapsedFormatter.swift Tests/ElapsedFormatterTests/main.swift -o "$TMP/fmt"
"$TMP/fmt" || fail=1
rm -rf "$TMP"

echo -e "\n${BOLD}3/6  Focus targeting (process ancestry + window matching)${RESET}"
TMP=$(mktemp -d)
swiftc -O NotchSoGood/Utilities/ProcessTree.swift NotchSoGood/Utilities/WindowMatcher.swift \
    Tests/FocusTargetingTests/main.swift -o "$TMP/focus"
"$TMP/focus" || fail=1
rm -rf "$TMP"

echo -e "\n${BOLD}4/6  Usage-limit parsing (recorded API response)${RESET}"
TMP=$(mktemp -d)
swiftc -O NotchSoGood/Services/UsageLimitsParser.swift Tests/UsageLimitsTests/main.swift -o "$TMP/limits"
"$TMP/limits" | tail -3 || fail=1
rm -rf "$TMP"

echo -e "\n${BOLD}5/6  Multi-display routing${RESET}"
TMP=$(mktemp -d)
swiftc -O NotchSoGood/Utilities/DisplayRouter.swift NotchSoGood/Utilities/NotchGeometry.swift \
  NotchSoGood/Utilities/ProcessTree.swift NotchSoGood/Models/NotchNotification.swift \
  NotchSoGood/Models/NotificationType.swift NotchSoGood/Views/MascotView.swift \
  Tests/DisplayTests/main.swift -o "$TMP/display"
"$TMP/display" | tail -3 || fail=1
rm -rf "$TMP"

echo -e "\n${BOLD}6/6  Hook bridge${RESET}"
python3 HookInstaller/test_hook.py 2>&1 | tail -4 || fail=1

echo ""
if [ "$fail" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All checks passed.${RESET}"
    echo -e "For the end-to-end UI checks, launch the app then run:"
    echo -e "  python3 HookInstaller/integration_test.py --shots /tmp/nsg-shots"
else
    echo -e "${RED}${BOLD}Some checks failed.${RESET}"; exit 1
fi
