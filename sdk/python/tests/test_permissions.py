"""Per-command permission-matrix tests.

Loads the canonical matrix from sdk/protocol/permissions.json and asserts that
the Python SDK's own command -> required-permission map matches it exactly, so
any future drift between the three SDKs is caught here.
"""

import json
import os

import pytest

from nanolink.command import Command, CommandType
from nanolink.connection import AgentConnection


PERMISSIONS_JSON = os.path.normpath(
    os.path.join(
        os.path.dirname(__file__), "..", "..", "protocol", "permissions.json"
    )
)


def _load_matrix():
    with open(PERMISSIONS_JSON, "r", encoding="utf-8") as fh:
        return json.load(fh)


def test_permissions_json_exists():
    assert os.path.isfile(PERMISSIONS_JSON), f"missing {PERMISSIONS_JSON}"


def test_required_permission_matrix():
    """Every CommandType resolves to the canonical required level."""
    matrix = _load_matrix()
    conn = AgentConnection()

    by_name = {entry["name"]: entry for entry in matrix["commands"]}

    # The canonical matrix and the Python enum must describe the same command set.
    enum_names = {ct.name for ct in CommandType}
    json_names = set(by_name.keys())
    assert enum_names == json_names, (
        f"command set drift: only-in-enum={enum_names - json_names}, "
        f"only-in-json={json_names - enum_names}"
    )

    for entry in matrix["commands"]:
        name = entry["name"]
        ct = CommandType[name]
        # Numeric code must match too.
        assert int(ct) == entry["code"], (
            f"{name}: enum code {int(ct)} != json code {entry['code']}"
        )
        cmd = Command(command_type=ct)
        actual = conn._get_required_permission(cmd)
        assert actual == entry["level"], (
            f"{name} (code {entry['code']}): got level {actual}, "
            f"expected {entry['level']}"
        )


def test_default_unknown_is_fail_closed():
    """An out-of-range command code falls through to the fail-closed default."""
    matrix = _load_matrix()
    conn = AgentConnection()
    # 9999 is not a defined CommandType; the resolver must fail closed.
    cmd = Command(command_type=9999)
    assert conn._get_required_permission(cmd) == matrix["default"]
