// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";
import {FlyoverTestBase} from "../helpers/FlyoverTestBase.sol";
import {PauseSystem} from "../../script/tasks/PauseSystem.s.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";

/**
 * @title PauseSystemTest
 * @notice Test for the pause-system task: registry from env, verify all contracts use same registry
 * @dev Uses mocks that expose pauseRegistry() and delegate pauseStatus() to the registry.
 */
contract PauseSystemTest is FlyoverTestBase {
    PauseSystem public pauseScript;

    MockPauseRegistry public mockRegistry;
    MockPausableContract public mockDiscovery;
    MockPausableContract public mockPegIn;
    MockPausableContract public mockPegOut;
    MockPausableContract public mockCollateral;

    function setUp() public {
        mockRegistry = new MockPauseRegistry();

        mockDiscovery = new MockPausableContract(
            "FlyoverDiscovery",
            mockRegistry
        );
        mockPegIn = new MockPausableContract("PegInContract", mockRegistry);
        mockPegOut = new MockPausableContract("PegOutContract", mockRegistry);
        mockCollateral = new MockPausableContract(
            "CollateralManagement",
            mockRegistry
        );

        console.log("Mock contracts deployed:");
        console.log("  PauseRegistry:", address(mockRegistry));
        console.log("  FlyoverDiscovery:", address(mockDiscovery));
        console.log("  PegInContract:", address(mockPegIn));
        console.log("  PegOutContract:", address(mockPegOut));
        console.log("  CollateralManagement:", address(mockCollateral));

        pauseScript = new PauseSystem();
    }

    /**
     * @notice Set environment variables: registry from env, and all four contract addresses
     */
    function _setEnvVars() internal {
        vm.setEnv("PAUSE_REGISTRY_ADDRESS", vm.toString(address(mockRegistry)));
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

        (bool r1, , ) = mockRegistry.pauseStatus();
        assertFalse(r1, "Registry should not be paused initially");

        pauseScript.checkStatus();

        // Pause the registry (central source of truth)
        mockRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Soft,
            "Test pause for status check"
        );

        (r1, , ) = mockRegistry.pauseStatus();
        assertTrue(r1, "Registry should be paused");

        _setEnvVars();
        pauseScript.checkStatus();

        console.log("\n[PASS] PauseSystem checkStatus works correctly!");
    }

    function test_RegistryPauseAffectsAllContracts() public {
        console.log("\n=== TEST REGISTRY PAUSE AFFECTS ALL ===\n");

        (bool d1, , ) = mockDiscovery.pauseStatus();
        (bool p1, , ) = mockPegIn.pauseStatus();
        (bool p2, , ) = mockPegOut.pauseStatus();
        (bool c1, , ) = mockCollateral.pauseStatus();

        assertFalse(d1 || p1 || p2 || c1, "None should be paused initially");

        mockRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Soft,
            "Test emergency pause"
        );

        (d1, , ) = mockDiscovery.pauseStatus();
        (p1, , ) = mockPegIn.pauseStatus();
        (p2, , ) = mockPegOut.pauseStatus();
        (c1, , ) = mockCollateral.pauseStatus();

        assertTrue(d1, "Discovery should report paused (from registry)");
        assertTrue(p1, "PegIn should report paused (from registry)");
        assertTrue(p2, "PegOut should report paused (from registry)");
        assertTrue(c1, "Collateral should report paused (from registry)");

        mockRegistry.setPauseLevel(IPauseRegistry.PauseLevel.None, "");

        (d1, , ) = mockDiscovery.pauseStatus();
        (p1, , ) = mockPegIn.pauseStatus();
        (p2, , ) = mockPegOut.pauseStatus();
        (c1, , ) = mockCollateral.pauseStatus();

        assertFalse(d1, "Discovery should report unpaused");
        assertFalse(p1, "PegIn should report unpaused");
        assertFalse(p2, "PegOut should report unpaused");
        assertFalse(c1, "Collateral should report unpaused");

        console.log("\n[PASS] Registry pause/unpause affects all contracts!");
    }

    function test_UnpauseAllContracts() public {
        console.log("\n=== TEST UNPAUSE ALL CONTRACTS ===\n");

        mockRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Soft,
            "Setup for unpause test"
        );

        (bool r1, , ) = mockRegistry.pauseStatus();
        assertTrue(r1, "Registry should be paused");

        mockRegistry.setPauseLevel(IPauseRegistry.PauseLevel.None, "");

        (r1, , ) = mockRegistry.pauseStatus();
        assertFalse(r1, "Registry should be unpaused");

        (bool d1, string memory dReason, ) = mockDiscovery.pauseStatus();
        (bool p1, string memory pReason, ) = mockPegIn.pauseStatus();
        (bool p2, string memory p2Reason, ) = mockPegOut.pauseStatus();
        (bool c1, string memory cReason, ) = mockCollateral.pauseStatus();

        assertFalse(d1 || p1 || p2 || c1, "All should be unpaused");
        assertEq(dReason, "", "Discovery reason should be cleared");
        assertEq(pReason, "", "PegIn reason should be cleared");
        assertEq(p2Reason, "", "PegOut reason should be cleared");
        assertEq(cReason, "", "Collateral reason should be cleared");

        console.log("\n[PASS] All contracts unpaused successfully!");
    }

    function test_CompleteCycle() public {
        _setEnvVars();
        console.log("\n=== TEST COMPLETE PAUSE/UNPAUSE CYCLE ===\n");

        console.log("1. Initial status check");
        pauseScript.checkStatus();

        console.log("\n2. Pausing via registry");
        mockRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Soft,
            "Integration test"
        );

        console.log("\n3. Status while paused");
        _setEnvVars();
        pauseScript.checkStatus();

        console.log("\n4. Unpausing registry");
        mockRegistry.setPauseLevel(IPauseRegistry.PauseLevel.None, "");

        console.log("\n5. Final status check");
        _setEnvVars();
        pauseScript.checkStatus();

        console.log("\n[PASS] Complete cycle successful!");
    }

    function test_PauseAllViaScript() public {
        _setEnvVars();
        console.log("\n=== TEST PAUSE ALL VIA SCRIPT ===\n");

        pauseScript.pauseAll("Script-initiated pause");

        (bool r1, string memory rReason, ) = mockRegistry.pauseStatus();
        assertTrue(r1, "Registry should be paused");
        assertEq(rReason, "Script-initiated pause", "Reason should match");

        (bool d1, string memory dReason, ) = mockDiscovery.pauseStatus();
        (bool p1, string memory pReason, ) = mockPegIn.pauseStatus();
        (bool p2, string memory p2Reason, ) = mockPegOut.pauseStatus();
        (bool c1, string memory cReason, ) = mockCollateral.pauseStatus();

        assertTrue(d1 && p1 && p2 && c1, "All should report paused");
        assertEq(dReason, "Script-initiated pause", "Reason should match");
        assertEq(pReason, "Script-initiated pause", "Reason should match");
        assertEq(p2Reason, "Script-initiated pause", "Reason should match");
        assertEq(cReason, "Script-initiated pause", "Reason should match");

        console.log("\n[PASS] pauseAll script function works correctly!");
    }

    function test_UnpauseAllViaScript() public {
        _setEnvVars();
        console.log("\n=== TEST UNPAUSE ALL VIA SCRIPT ===\n");

        pauseScript.pauseAll("Pre-test pause");
        pauseScript.unpauseAll();

        (bool r1, , ) = mockRegistry.pauseStatus();
        assertFalse(r1, "Registry should be unpaused");

        (bool d1, , ) = mockDiscovery.pauseStatus();
        (bool p1, , ) = mockPegIn.pauseStatus();
        (bool p2, , ) = mockPegOut.pauseStatus();
        (bool c1, , ) = mockCollateral.pauseStatus();

        assertFalse(d1 || p1 || p2 || c1, "All should report unpaused");

        console.log("\n[PASS] unpauseAll script function works correctly!");
    }

    function test_RevertsWhenContractHasDifferentRegistry() public {
        _setEnvVars();

        // Deploy another registry and a mock that points to it
        MockPauseRegistry otherRegistry = new MockPauseRegistry();
        MockPausableContract mockWithOtherRegistry = new MockPausableContract(
            "Other",
            otherRegistry
        );

        // Point PegIn to a contract that has a *different* registry
        vm.setEnv(
            "PEGIN_CONTRACT_ADDRESS",
            vm.toString(address(mockWithOtherRegistry))
        );

        vm.expectRevert(
            "PauseSystem: PegInContract has different PauseRegistry"
        );
        pauseScript.checkStatus();
    }

    function test_RevertsWhenPegOutHasDifferentRegistry() public {
        _setEnvVars();

        MockPauseRegistry otherRegistry = new MockPauseRegistry();
        MockPausableContract mockWithOtherRegistry = new MockPausableContract(
            "Other",
            otherRegistry
        );

        vm.setEnv(
            "PEGOUT_CONTRACT_ADDRESS",
            vm.toString(address(mockWithOtherRegistry))
        );

        vm.expectRevert(
            "PauseSystem: PegOutContract has different PauseRegistry"
        );
        pauseScript.checkStatus();
    }

    function test_RevertsWhenCollateralHasDifferentRegistry() public {
        _setEnvVars();

        MockPauseRegistry otherRegistry = new MockPauseRegistry();
        MockPausableContract mockWithOtherRegistry = new MockPausableContract(
            "Other",
            otherRegistry
        );

        vm.setEnv(
            "COLLATERAL_MANAGEMENT_ADDRESS",
            vm.toString(address(mockWithOtherRegistry))
        );

        vm.expectRevert(
            "PauseSystem: CollateralManagement has different PauseRegistry"
        );
        pauseScript.checkStatus();
    }

    function test_RevertsWhenDiscoveryHasDifferentRegistry() public {
        _setEnvVars();

        MockPauseRegistry otherRegistry = new MockPauseRegistry();
        MockPausableContract mockWithOtherRegistry = new MockPausableContract(
            "Other",
            otherRegistry
        );

        vm.setEnv(
            "FLYOVER_DISCOVERY_ADDRESS",
            vm.toString(address(mockWithOtherRegistry))
        );

        vm.expectRevert(
            "PauseSystem: FlyoverDiscovery has different PauseRegistry"
        );
        pauseScript.checkStatus();
    }
}

/**
 * @notice Mock PauseRegistry: central pause state used by the script
 */
contract MockPauseRegistry is IPauseRegistry {
    bool private _paused;
    string private _reason;
    uint64 private _since;
    PauseLevel private _level;

    function paused() external view override returns (bool) {
        return _paused;
    }

    function pauseStatus()
        external
        view
        override
        returns (bool isPaused, string memory reason, uint64 since)
    {
        return (_paused, _reason, _since);
    }

    function pauseLevel() external view override returns (PauseLevel) {
        return _level;
    }

    function setPauseLevel(
        PauseLevel level,
        string calldata reason
    ) external override {
        _setPauseLevel(level, reason);
    }

    function _setPauseLevel(PauseLevel level, string memory reason) internal {
        bool wasPaused = _paused;
        _level = level;
        _paused = (level != PauseLevel.None);
        if (_paused) {
            if (!wasPaused) {
                _since = uint64(block.timestamp);
            }
            _reason = reason;
        } else {
            _reason = "";
            _since = 0;
        }
    }

    function hardPausesCount() external pure override returns (uint256) {
        return 0;
    }

    function hardPauses(
        uint256
    ) external pure override returns (uint64, uint64, uint64, uint64) {
        return (0, 0, 0, 0);
    }

    function computePauseOverlap(
        uint256,
        uint256
    ) external pure override returns (uint256) {
        return 0;
    }

    function computePauseOverlapBlocks(
        uint256,
        uint256
    ) external pure override returns (uint256) {
        return 0;
    }
}

/**
 * @notice Mock contract that exposes pauseRegistry() and delegates pauseStatus() to the registry
 */
contract MockPausableContract {
    string public name;
    IPauseRegistry private _registry;

    constructor(string memory _name, IPauseRegistry registry) {
        name = _name;
        _registry = registry;
    }

    function pauseRegistry() external view returns (IPauseRegistry) {
        return _registry;
    }

    function pauseStatus()
        external
        view
        returns (bool isPaused, string memory reason, uint64 since)
    {
        return _registry.pauseStatus();
    }
}
