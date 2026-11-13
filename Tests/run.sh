#!/bin/zsh
# Logic tests, on the Mac: everything that doesn't need a watch (stream parsing, errors, models,
# answer text, conversation, install dates and reminders, spending, prompt). Also fails if an em
# or en dash slipped into the app's sources.
#
#   Tests/run.sh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build

if /usr/bin/grep -rnE $'—|–' GrokWatch --include='*.swift'; then
  echo "Long dash found in the sources above."
  exit 1
fi

xcrun swiftc -swift-version 5 -default-isolation MainActor -parse-as-library \
  GrokWatch/Grok/SSEParser.swift \
  GrokWatch/Grok/GrokClient.swift \
  GrokWatch/Grok/ModelChoice.swift \
  GrokWatch/Grok/Prompt.swift \
  GrokWatch/Chat/ChatMessage.swift \
  GrokWatch/Chat/AnswerText.swift \
  GrokWatch/System/ProvisioningProfile.swift \
  GrokWatch/System/Spending.swift \
  Tests/LogicTests.swift \
  -o build/logic-tests

build/logic-tests
