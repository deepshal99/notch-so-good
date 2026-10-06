#!/bin/bash
# Runs every automated check in the project.
#   bash run-tests.sh
set -e
set -o pipefail  # a failing test binary must fail its step, not be hidden by `tail`
cd "$(dirname "$0")"

BOLD='\033[1m'; GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
fail=0

echo -e "\n${BOLD}1/9  Release build${RESET}"
build_status=0
build_log=$(swift build -c release 2>&1) || build_status=$?
if [ "$build_status" -ne 0 ] || grep -E "error:|warning:" <<< "$build_log"; then
    echo -e "  ${RED}build produced errors/warnings${RESET}"; fail=1
else
    echo -e "  ${GREEN}✓${RESET} builds clean"
fi

echo -e "\n${BOLD}2/9  Elapsed-time formatting${RESET}"
TMP=$(mktemp -d)
swiftc -O NotchSoGood/Utilities/ElapsedFormatter.swift Tests/ElapsedFormatterTests/main.swift -o "$TMP/fmt"
"$TMP/fmt" || fail=1
rm -rf "$TMP"

echo -e "\n${BOLD}3/9  Focus targeting (process ancestry + window matching)${RESET}"
TMP=$(mktemp -d)
swiftc -O NotchSoGood/Utilities/ProcessTree.swift NotchSoGood/Utilities/WindowMatcher.swift \
    Tests/FocusTargetingTests/main.swift -o "$TMP/focus"
"$TMP/focus" || fail=1
rm -rf "$TMP"

echo -e "\n${BOLD}4/9  Usage-limit parsing (recorded API response)${RESET}"
TMP=$(mktemp -d)
swiftc -O NotchSoGood/Services/UsageLimitsParser.swift Tests/UsageLimitsTests/main.swift -o "$TMP/limits"
"$TMP/limits" | tail -3 || fail=1
rm -rf "$TMP"

echo -e "\n${BOLD}5/9  Multi-display routing${RESET}"
TMP=$(mktemp -d)
swiftc -O NotchSoGood/Utilities/DisplayRouter.swift NotchSoGood/Utilities/NotchGeometry.swift \
  NotchSoGood/Utilities/ProcessTree.swift NotchSoGood/Models/NotchNotification.swift \
  NotchSoGood/Models/NotificationType.swift NotchSoGood/Utilities/ColorHex.swift \
  Tests/DisplayTests/main.swift -o "$TMP/display"
"$TMP/display" | tail -3 || fail=1
rm -rf "$TMP"

echo -e "\n${BOLD}6/9  Destructive-command hints${RESET}"
TMP=$(mktemp -d)
swiftc -O NotchSoGood/Utilities/CommandRisk.swift Tests/CommandRiskTests/main.swift -o "$TMP/risk"
"$TMP/risk" | tail -3 || fail=1
rm -rf "$TMP"

echo -e "\n${BOLD}7/9  Character engine${RESET}"
TMP=$(mktemp -d)
swiftc -O NotchSoGood/Character/CharacterModel.swift NotchSoGood/Character/CharacterEngine.swift \
  NotchSoGood/Character/CharacterStateMapping.swift NotchSoGood/Models/NotchNotification.swift \
  NotchSoGood/Models/NotificationType.swift NotchSoGood/Utilities/ColorHex.swift \
  Tests/CharacterEngineTests/main.swift -o "$TMP/character"
"$TMP/character" | tail -4 || fail=1
rm -rf "$TMP"

echo -e "\n${BOLD}8/9  Usage forecast${RESET}"
TMP=$(mktemp -d)
swiftc -O NotchSoGood/Utilities/UsageForecast.swift Tests/UsageForecastTests/main.swift -o "$TMP/forecast"
"$TMP/forecast" | tail -3 || fail=1
rm -rf "$TMP"

echo -e "\n${BOLD}9/9  Hook bridge${RESET}"
python3 HookInstaller/test_hook.py 2>&1 | tail -4 || fail=1

echo ""
if [ "$fail" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All checks passed.${RESET}"
    echo -e "For the end-to-end UI checks, launch the app then run:"
    echo -e "  python3 HookInstaller/integration_test.py --shots /tmp/nsg-shots"
else
    echo -e "${RED}${BOLD}Some checks failed.${RESET}"; exit 1
fi
