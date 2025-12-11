// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";
import {FlyoverTestBase} from "../helpers/FlyoverTestBase.sol";
import {PauseSystem} from "../../script/tasks/PauseSystem.s.sol";

/**
 * @title PauseSystemTest
 * @notice Test for the pause-system task with new Flyover contracts
 * @dev Uses direct contract calls to avoid env var race conditions with parallel tests
 */
contract PauseSystemTest is FlyoverTestBase {
    PauseSystem public pauseScript;

    MockPausableContract public mockDiscovery;
    MockPausableContract public mockPegIn;
    MockPausableContract public mockPegOut;
    MockPausableContract public mockCollateral;

    function setUp() public {
        mockDiscovery = new MockPausableContract("FlyoverDiscovery");
        mockPegIn = new MockPausableContract("PegInContract");
        mockPegOut = new MockPausableContract("PegOutContract");
        mockCollateral = new MockPausableContract("CollateralManagement");

        console.log("Mock contracts deployed:");
        console.log("  FlyoverDiscovery:", address(mockDiscovery));
        console.log("  PegInContract:", address(mockPegIn));
        console.log("  PegOutContract:", address(mockPegOut));
        console.log("  CollateralManagement:", address(mockCollateral));

        pauseScript = new PauseSystem();
    }

    /**
     * @notice Set environment variables to point to our mock contracts
     */
    function _setEnvVars() internal {
        vm.setEnv(
            "FLYOVER_DISCOVERY_ADDRESS",
            vm.toString(address(mockDiscovery))
        );
        vm.setEnv("PEGIN_CONTRACT_ADDRESS", vm.toString(address(mockPegIn)));
        vm.setEnv("PEGOUT_CONTRACT_ADDRESS", vm.toString(address(mockPegOut)));
        vm.setEnv(
            "COLLATERAL_MANAGEMENT_ADDRESS",
            vm.toString(address(mockCollateral))
        );
    }

    function test_CheckStatus() public {
        _setEnvVars();
        console.log("\n=== TEST CHECK STATUS ===\n");

        (bool d1, , ) = mockDiscovery.pauseStatus();
        (bool p1, , ) = mockPegIn.pauseStatus();
        (bool p2, , ) = mockPegOut.pauseStatus();
        (bool c1, , ) = mockCollateral.pauseStatus();

        assertFalse(d1, "Discovery should not be paused initially");
        assertFalse(p1, "PegIn should not be paused initially");
        assertFalse(p2, "PegOut should not be paused initially");
        assertFalse(c1, "Collateral should not be paused initially");

        pauseScript.checkStatus();

        // Directly pause contracts
        string memory reason = "Test pause for status check";
        mockDiscovery.pause(reason);
        mockPegIn.pause(reason);
        mockPegOut.pause(reason);
        mockCollateral.pause(reason);

        (d1, , ) = mockDiscovery.pauseStatus();
        (p1, , ) = mockPegIn.pauseStatus();
        (p2, , ) = mockPegOut.pauseStatus();
        (c1, , ) = mockCollateral.pauseStatus();

        assertTrue(d1, "Discovery should be paused");
        assertTrue(p1, "PegIn should be paused");
        assertTrue(p2, "PegOut should be paused");
        assertTrue(c1, "Collateral should be paused");

        _setEnvVars();
        pauseScript.checkStatus();

        console.log("\n[PASS] PauseSystem checkStatus works correctly!");
    }

    function test_PauseAllContracts() public {
        console.log("\n=== TEST PAUSE ALL CONTRACTS ===\n");

        (bool d1, , ) = mockDiscovery.pauseStatus();
        (bool p1, , ) = mockPegIn.pauseStatus();
        (bool p2, , ) = mockPegOut.pauseStatus();
        (bool c1, , ) = mockCollateral.pauseStatus();

        assertFalse(d1, "Discovery should not be paused initially");
        assertFalse(p1, "PegIn should not be paused initially");
        assertFalse(p2, "PegOut should not be paused initially");
        assertFalse(c1, "Collateral should not be paused initially");

        // Directly pause contracts to avoid env var race conditions
        string memory reason = "Test emergency pause";
        mockDiscovery.pause(reason);
        mockPegIn.pause(reason);
        mockPegOut.pause(reason);
        mockCollateral.pause(reason);

        string memory dReason;
        string memory pReason;
        string memory p2Reason;
        string memory cReason;

        (d1, dReason, ) = mockDiscovery.pauseStatus();
        (p1, pReason, ) = mockPegIn.pauseStatus();
        (p2, p2Reason, ) = mockPegOut.pauseStatus();
        (c1, cReason, ) = mockCollateral.pauseStatus();

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

        // Directly pause then unpause
        string memory pauseReason = "Setup for unpause test";
        mockDiscovery.pause(pauseReason);
        mockPegIn.pause(pauseReason);
        mockPegOut.pause(pauseReason);
        mockCollateral.pause(pauseReason);

        (bool d1, , ) = mockDiscovery.pauseStatus();
        (bool p1, , ) = mockPegIn.pauseStatus();
        (bool p2, , ) = mockPegOut.pauseStatus();
        (bool c1, , ) = mockCollateral.pauseStatus();

        assertTrue(d1 && p1 && p2 && c1, "All should be paused");

        mockDiscovery.unpause();
        mockPegIn.unpause();
        mockPegOut.unpause();
        mockCollateral.unpause();

        string memory dReason;
        string memory pReason;
        string memory p2Reason;
        string memory cReason;

        (d1, dReason, ) = mockDiscovery.pauseStatus();
        (p1, pReason, ) = mockPegIn.pauseStatus();
        (p2, p2Reason, ) = mockPegOut.pauseStatus();
        (c1, cReason, ) = mockCollateral.pauseStatus();

        assertFalse(d1, "Discovery should be unpaused");
        assertFalse(p1, "PegIn should be unpaused");
        assertFalse(p2, "PegOut should be unpaused");
        assertFalse(c1, "Collateral should be unpaused");

        assertEq(dReason, "", "Discovery reason should be cleared");
        assertEq(pReason, "", "PegIn reason should be cleared");
        assertEq(p2Reason, "", "PegOut reason should be cleared");
        assertEq(cReason, "", "Collateral reason should be cleared");

        console.log("\n[PASS] All contracts unpaused successfully!");
    }

    function test_CompleteCycle() public {
        _setEnvVars();
        console.log("\n=== TEST COMPLETE PAUSE/UNPAUSE CYCLE ===\n");

        string memory reason = "Integration test";

        console.log("1. Initial status check");
        pauseScript.checkStatus();

        console.log("\n2. Pausing all contracts");
        mockDiscovery.pause(reason);
        mockPegIn.pause(reason);
        mockPegOut.pause(reason);
        mockCollateral.pause(reason);

        console.log("\n3. Status while paused");
        _setEnvVars();
        pauseScript.checkStatus();

        console.log("\n4. Unpausing all contracts");
        mockDiscovery.unpause();
        mockPegIn.unpause();
        mockPegOut.unpause();
        mockCollateral.unpause();

        console.log("\n5. Final status check");
        _setEnvVars();
        pauseScript.checkStatus();

        console.log("\n[PASS] Complete cycle successful!");
    }

    function test_PauseAllViaScript() public {
        _setEnvVars();
        console.log("\n=== TEST PAUSE ALL VIA SCRIPT ===\n");

        // Test that the script's pauseAll function works correctly
        pauseScript.pauseAll("Script-initiated pause");

        (bool d1, string memory dReason, ) = mockDiscovery.pauseStatus();
        (bool p1, string memory pReason, ) = mockPegIn.pauseStatus();
        (bool p2, string memory p2Reason, ) = mockPegOut.pauseStatus();
        (bool c1, string memory cReason, ) = mockCollateral.pauseStatus();

        assertTrue(d1, "Discovery should be paused");
        assertTrue(p1, "PegIn should be paused");
        assertTrue(p2, "PegOut should be paused");
        assertTrue(c1, "Collateral should be paused");

        assertEq(dReason, "Script-initiated pause", "Reason should match");
        assertEq(pReason, "Script-initiated pause", "Reason should match");
        assertEq(p2Reason, "Script-initiated pause", "Reason should match");
        assertEq(cReason, "Script-initiated pause", "Reason should match");

        console.log("\n[PASS] pauseAll script function works correctly!");
    }

    function test_UnpauseAllViaScript() public {
        _setEnvVars();
        console.log("\n=== TEST UNPAUSE ALL VIA SCRIPT ===\n");

        // First pause all
        pauseScript.pauseAll("Pre-test pause");

        // Then unpause via script
        pauseScript.unpauseAll();

        (bool d1, , ) = mockDiscovery.pauseStatus();
        (bool p1, , ) = mockPegIn.pauseStatus();
        (bool p2, , ) = mockPegOut.pauseStatus();
        (bool c1, , ) = mockCollateral.pauseStatus();

        assertFalse(d1, "Discovery should be unpaused");
        assertFalse(p1, "PegIn should be unpaused");
        assertFalse(p2, "PegOut should be unpaused");
        assertFalse(c1, "Collateral should be unpaused");

        console.log("\n[PASS] unpauseAll script function works correctly!");
    }
}

/**
 * @notice Mock pausable contract matching the new Flyover contract interface
 */
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
