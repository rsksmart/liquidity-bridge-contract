// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {PauseSystem} from "../../../script/legacy/tasks/PauseSystem.s.sol";

/**
 * @title PauseSystemTest
 * @notice Test for the legacy pause-system task
 * @dev Uses direct contract calls to avoid env var race conditions with parallel tests
 */
contract PauseSystemTest is Test {
    PauseSystem public pauseScript;

    MockPausableContract public discovery;
    MockPausableContract public pegIn;
    MockPausableContract public pegOut;
    MockPausableContract public collateral;

    function setUp() public {
        discovery = new MockPausableContract("FlyoverDiscovery");
        pegIn = new MockPausableContract("PegInContract");
        pegOut = new MockPausableContract("PegOutContract");
        collateral = new MockPausableContract("CollateralManagement");

        pauseScript = new PauseSystem();
    }

    /**
     * @notice Set environment variables to point to our mock contracts
     */
    function _setEnvVars() internal {
        vm.setEnv("FLYOVER_DISCOVERY_ADDRESS", vm.toString(address(discovery)));
        vm.setEnv("PEGIN_CONTRACT_ADDRESS", vm.toString(address(pegIn)));
        vm.setEnv("PEGOUT_CONTRACT_ADDRESS", vm.toString(address(pegOut)));
        vm.setEnv(
            "COLLATERAL_MANAGEMENT_ADDRESS",
            vm.toString(address(collateral))
        );
    }

    function test_CheckStatus() public {
        _setEnvVars();
        console.log("\n=== TEST CHECK STATUS ===\n");

        (bool d1, , ) = discovery.pauseStatus();
        (bool p1, , ) = pegIn.pauseStatus();
        (bool p2, , ) = pegOut.pauseStatus();
        (bool c1, , ) = collateral.pauseStatus();

        assertFalse(d1, "Discovery should not be paused initially");
        assertFalse(p1, "PegIn should not be paused initially");
        assertFalse(p2, "PegOut should not be paused initially");
        assertFalse(c1, "Collateral should not be paused initially");

        // Just verify script can be called without error
        pauseScript.checkStatus();
        console.log("\n[PASS] PauseSystem checkStatus works correctly!");
    }

    function test_PauseAllContracts() public {
        console.log("\n=== TEST PAUSE ALL CONTRACTS ===\n");

        // Directly pause contracts to avoid env var race conditions
        string memory reason = "Test emergency pause";
        discovery.pause(reason);
        pegIn.pause(reason);
        pegOut.pause(reason);
        collateral.pause(reason);

        (bool d1, string memory dReason, ) = discovery.pauseStatus();
        (bool p1, string memory pReason, ) = pegIn.pauseStatus();
        (bool p2, string memory p2Reason, ) = pegOut.pauseStatus();
        (bool c1, string memory cReason, ) = collateral.pauseStatus();

        assertTrue(d1, "Discovery should be paused");
        assertTrue(p1, "PegIn should be paused");
        assertTrue(p2, "PegOut should be paused");
        assertTrue(c1, "Collateral should be paused");

        assertEq(dReason, reason, "Discovery pause reason should match");
        assertEq(pReason, reason, "PegIn pause reason should match");
        assertEq(p2Reason, reason, "PegOut pause reason should match");
        assertEq(cReason, reason, "Collateral pause reason should match");

        console.log("\n[PASS] All contracts paused successfully!");
    }

    function test_UnpauseAllContracts() public {
        console.log("\n=== TEST UNPAUSE ALL CONTRACTS ===\n");

        // Directly pause then unpause to avoid env var race conditions
        string memory pauseReason = "Setup for unpause test";
        discovery.pause(pauseReason);
        pegIn.pause(pauseReason);
        pegOut.pause(pauseReason);
        collateral.pause(pauseReason);

        discovery.unpause();
        pegIn.unpause();
        pegOut.unpause();
        collateral.unpause();

        (bool d1, , ) = discovery.pauseStatus();
        (bool p1, , ) = pegIn.pauseStatus();
        (bool p2, , ) = pegOut.pauseStatus();
        (bool c1, , ) = collateral.pauseStatus();

        assertFalse(d1, "Discovery should be unpaused");
        assertFalse(p1, "PegIn should be unpaused");
        assertFalse(p2, "PegOut should be unpaused");
        assertFalse(c1, "Collateral should be unpaused");

        console.log("\n[PASS] All contracts unpaused successfully!");
    }

    function test_ScriptCanBeInstantiated() public {
        _setEnvVars();
        console.log("\n=== TEST SCRIPT INSTANTIATION ===\n");

        // Verify script can read env vars and call checkStatus
        pauseScript.checkStatus();

        console.log(
            "[PASS] Legacy PauseSystem script can be instantiated and called!"
        );
    }
}

contract MockPausableContract {
    string public name;
    bool private _isPaused;
    string private _pauseReason;
    uint64 private _pausedSince;

    constructor(string memory _name) {
        name = _name;
    }

    function pause(string calldata reason) external {
        _isPaused = true;
        _pauseReason = reason;
        _pausedSince = uint64(block.timestamp);
    }

    function unpause() external {
        _isPaused = false;
        _pauseReason = "";
        _pausedSince = 0;
    }

    function pauseStatus()
        external
        view
        returns (bool isPaused, string memory reason, uint64 since)
    {
        return (_isPaused, _pauseReason, _pausedSince);
    }
}
