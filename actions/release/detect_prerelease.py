#!/usr/bin/env python3
import re
import sys

version = sys.argv[1]
PRE_BUMP_TYPES = {"prepatch", "preminor", "premajor", "prerelease"}
if version in PRE_BUMP_TYPES or re.search(r'(\.dev\d*|rc\d*|alpha\d*|beta\d*|a\d+|b\d+)', version):
    print("true")
else:
    print("false")
