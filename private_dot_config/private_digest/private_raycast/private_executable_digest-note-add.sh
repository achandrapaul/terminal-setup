#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Add Digest Note
# @raycast.mode silent
# @raycast.packageName Digest
# @raycast.icon 📝
# @raycast.argument1 { "type": "text", "placeholder": "Note" }

'/Users/achandrapaul/.config/bin/digest' note add "$1"
