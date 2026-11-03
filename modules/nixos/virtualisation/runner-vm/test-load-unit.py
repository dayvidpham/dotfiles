#!/usr/bin/env python3
"""Check the rendered image-loader unit and reject the old misplacement."""
import configparser
from pathlib import Path
import sys


def valid(text):
    unit = configparser.ConfigParser(interpolation=None, strict=False)
    unit.optionxform = str
    unit.read_string(text)
    growfs = 'systemd-growfs@var-lib-containers.service'
    return (
        unit['Unit'].get('OnFailure') == 'poweroff.target'
        and 'OnFailure' not in unit['Service']
        and growfs in unit['Unit'].get('Requires', '').split()
        and growfs in unit['Unit'].get('After', '').split()
    )


text = Path(sys.argv[1]).read_text()
assert valid(text), 'rendered image-loader unit has an invalid failure policy or growfs dependency'
mutated = text.replace('OnFailure=poweroff.target\n', '', 1).replace(
    '[Service]\n', '[Service]\nOnFailure=poweroff.target\n', 1
)
assert not valid(mutated), 'misplaced OnFailure mutation escaped detection'
print('PASS rendered unit and misplaced-handler mutation')
