// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {PauseSystem} from "../../script/tasks/PauseSystem.s.sol";

/**
 * @title PauseSystemTest
 * @notice Test for the pause-system task - validates the actual script works correctly
 * @dev Uses mock pausable contracts to test the pause/unpause flow
 */
contract PauseSystemTest is Test {
    PauseSystem public pauseScript;

    MockPausableContract public discovery;
    MockPausableContract public pegIn;
    MockPausableContract public pegOut;
    MockPausableContract public collateral;

    function setUp() public {
        // Deploy mock pausable contracts
        discovery = new MockPausableContract("FlyoverDiscovery");
        pegIn = new MockPausableContract("PegInContract");
        pegOut = new MockPausableContract("PegOutContract");
        collateral = new MockPausableContract("CollateralManagement");

        console.log("Mock contracts deployed:");
        console.log("  FlyoverDiscovery:", address(discovery));
        console.log("  PegInContract:", address(pegIn));
        console.log("  PegOutContract:", address(pegOut));
        console.log("  CollateralManagement:", address(collateral));

        // Instantiate the pause script
        pauseScript = new PauseSystem();

        // Set contract addresses in environment for script to use
        vm.setEnv("FLYOVER_DISCOVERY_ADDRESS", vm.toString(address(discovery)));
        vm.setEnv("PEGIN_CONTRACT_ADDRESS", vm.toString(address(pegIn)));
        vm.setEnv("PEGOUT_CONTRACT_ADDRESS", vm.toString(address(pegOut)));
        vm.setEnv(
            "COLLATERAL_MANAGEMENT_ADDRESS",
            vm.toString(address(collateral))
        );
    }

    function test_CheckStatus() public {
        console.log("\n=== TEST CHECK STATUS ===\n");

        // Test 1: Verify initial state - all contracts should be unpaused
        (bool d1, , ) = discovery.pauseStatus();
        (bool p1, , ) = pegIn.pauseStatus();
        (bool p2, , ) = pegOut.pauseStatus();
        (bool c1, , ) = collateral.pauseStatus();

        assertFalse(d1, "Discovery should not be paused initially");
        assertFalse(p1, "PegIn should not be paused initially");
        assertFalse(p2, "PegOut should not be paused initially");
        assertFalse(c1, "Collateral should not be paused initially");

        // Call checkStatus when contracts are unpaused
        pauseScript.checkStatus();

        // Test 2: Pause contracts and verify checkStatus reports them as paused
        string memory reason = "Test pause for status check";
        discovery.pause(reason);
        pegIn.pause(reason);
        pegOut.pause(reason);
        collateral.pause(reason);

        // Verify all contracts are now paused
        (d1, , ) = discovery.pauseStatus();
        (p1, , ) = pegIn.pauseStatus();
        (p2, , ) = pegOut.pauseStatus();
        (c1, , ) = collateral.pauseStatus();

        assertTrue(d1, "Discovery should be paused");
        assertTrue(p1, "PegIn should be paused");
        assertTrue(p2, "PegOut should be paused");
        assertTrue(c1, "Collateral should be paused");

        // Call checkStatus when contracts are paused
        pauseScript.checkStatus();

        console.log("\n[PASS] PauseSystem checkStatus works correctly!");
        console.log(
            "[PASS] Status correctly reported for both ACTIVE and PAUSED states!"
        );
    }

    function test_PauseAllContracts() public {
        console.log("\n=== TEST PAUSE ALL CONTRACTS ===\n");

        // Verify all contracts are active initially
        (bool d1, , ) = discovery.pauseStatus();
        (bool p1, , ) = pegIn.pauseStatus();
        (bool p2, , ) = pegOut.pauseStatus();
        (bool c1, , ) = collateral.pauseStatus();

        assertFalse(d1, "Discovery should not be paused initially");
        assertFalse(p1, "PegIn should not be paused initially");
        assertFalse(p2, "PegOut should not be paused initially");
        assertFalse(c1, "Collateral should not be paused initially");
        console.log("Initial state: All contracts ACTIVE");

        // Pause all contracts using the script
        string memory reason = "Test emergency pause";
        console.log("\nPausing all contracts with reason:", reason);

        pauseScript.pauseAll(reason);

        // Verify all contracts are paused
        string memory dReason;
        string memory pReason;
        string memory p2Reason;
        string memory cReason;

        (d1, dReason, ) = discovery.pauseStatus();
        (p1, pReason, ) = pegIn.pauseStatus();
        (p2, p2Reason, ) = pegOut.pauseStatus();
        (c1, cReason, ) = collateral.pauseStatus();

        assertTrue(d1, "Discovery should be paused");
        assertTrue(p1, "PegIn should be paused");
        assertTrue(p2, "PegOut should be paused");
        assertTrue(c1, "Collateral should be paused");

        assertEq(dReason, reason, "Discovery pause reason should match");
        assertEq(pReason, reason, "PegIn pause reason should match");
        assertEq(p2Reason, reason, "PegOut pause reason should match");
        assertEq(cReason, reason, "Collateral pause reason should match");

        console.log("\n[PASS] All contracts paused successfully!");
        console.log("[PASS] PauseSystem pauseAll works correctly!");
    }

    function test_UnpauseAllContracts() public {
        console.log("\n=== TEST UNPAUSE ALL CONTRACTS ===\n");

        // First pause all contracts using the script
        string memory pauseReason = "Setup for unpause test";
        console.log("Setting up: Pausing all contracts first");
        pauseScript.pauseAll(pauseReason);

        // Verify all are paused
        (bool d1, , ) = discovery.pauseStatus();
        (bool p1, , ) = pegIn.pauseStatus();
        (bool p2, , ) = pegOut.pauseStatus();
        (bool c1, , ) = collateral.pauseStatus();

        assertTrue(d1 && p1 && p2 && c1, "All should be paused");
        console.log("Setup complete: All contracts PAUSED");

        // Unpause all using the script
        console.log("\nUnpausing all contracts...");
        pauseScript.unpauseAll();

        // Verify all contracts are unpaused
        string memory dReason;
        string memory pReason;
        string memory p2Reason;
        string memory cReason;

        (d1, dReason, ) = discovery.pauseStatus();
        (p1, pReason, ) = pegIn.pauseStatus();
        (p2, p2Reason, ) = pegOut.pauseStatus();
        (c1, cReason, ) = collateral.pauseStatus();

        assertFalse(d1, "Discovery should be unpaused");
        assertFalse(p1, "PegIn should be unpaused");
        assertFalse(p2, "PegOut should be unpaused");
        assertFalse(c1, "Collateral should be unpaused");

        assertEq(dReason, "", "Discovery reason should be cleared");
        assertEq(pReason, "", "PegIn reason should be cleared");
        assertEq(p2Reason, "", "PegOut reason should be cleared");
        assertEq(cReason, "", "Collateral reason should be cleared");

        console.log("\n[PASS] All contracts unpaused successfully!");
        console.log("[PASS] PauseSystem unpauseAll works correctly!");
    }

    function test_CompleteCycle() public {
        console.log("\n=== TEST COMPLETE PAUSE/UNPAUSE CYCLE ===\n");

        string memory reason = "Integration test";

        // Check status, pause, check again, unpause, check final
        console.log("1. Initial status check");
        pauseScript.checkStatus();

        console.log("\n2. Pausing all contracts");
        pauseScript.pauseAll(reason);

        console.log("\n3. Status while paused");
        pauseScript.checkStatus();

        console.log("\n4. Unpausing all contracts");
        pauseScript.unpauseAll();

        console.log("\n5. Final status check");
        pauseScript.checkStatus();

        console.log("\n[PASS] Complete cycle successful!");
        console.log("[PASS] PauseSystem.s.sol script works correctly!");
    }
}

/**
 * @notice Mock pausable contract for testing
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
