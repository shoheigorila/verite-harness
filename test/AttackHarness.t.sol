// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/AttackHarness.sol";

contract AttackHarnessTest {
    AttackHarness public harness;

    function setUp() public {
        harness = new AttackHarness();
    }

    function testGetActions() public view {
        AttackHarness.ActionSpec[] memory actions = harness.getActions();
        assert(actions.length == 11);

        // Check first action (erc20TransferBps)
        assert(actions[0].id == 1);
        assert(actions[0].argc == 3);

        // Check swap action
        assert(actions[1].id == 2);
        assert(actions[1].argc == 5);
    }

    function testBpsMax() public view {
        assert(harness.BPS_MAX() == 10000);
    }
}
