#!/usr/bin/env python3

import pip
import sys
from packaging.version import parse

PIP_VERSION = parse(pip.__version__)
MIN_VERSION = parse('23.1')

print(pip.__version__)

# needed == false == 0
sys.exit(PIP_VERSION >= MIN_VERSION)
