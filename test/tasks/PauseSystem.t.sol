// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {PauseSystem} from "../../script/tasks/PauseSystem.s.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";

/// @dev Mirrors PauseSystem registry checks with explicit addresses (parallel-safe; no vm.setEnv).
interface IPauseRegistryGetter {
    function pauseRegistry() external view returns (IPauseRegistry);
}

/// @dev Test-only helper: same behavior as PauseSystem but takes addresses as arguments.
contract PauseSystemTestRunner is PauseSystem {
    function _verifyAllContractsUseRegistryAt(
        IPauseRegistry registry,
        address pegInAddr,
        address pegOutAddr,
        address collateralAddr,
        address discoveryAddr
    ) internal view {
        address expected = address(registry);

        require(
            address(IPauseRegistryGetter(pegInAddr).pauseRegistry()) ==
                expected,
            "PauseSystem: PegInContract has different PauseRegistry"
        );
        require(
            address(IPauseRegistryGetter(pegOutAddr).pauseRegistry()) ==
                expected,
            "PauseSystem: PegOutContract has different PauseRegistry"
        );
        require(
            address(IPauseRegistryGetter(collateralAddr).pauseRegistry()) ==
                expected,
            "PauseSystem: CollateralManagement has different PauseRegistry"
        );
        require(
            address(IPauseRegistryGetter(discoveryAddr).pauseRegistry()) ==
                expected,
            "PauseSystem: FlyoverDiscovery has different PauseRegistry"
        );
    }

    function checkStatusAt(
        address registryAddr,
        address pegInAddr,
        address pegOutAddr,
        address collateralAddr,
        address discoveryAddr
    ) public view {
        console.log("\n=== FLYOVER PAUSE STATUS ===\n");

        IPauseRegistry registry = IPauseRegistry(registryAddr);
        _verifyAllContractsUseRegistryAt(
            registry,
            pegInAddr,
            pegOutAddr,
            collateralAddr,
            discoveryAddr
        );

        console.log(
            string.concat("PauseRegistry: ", vm.toString(address(registry)))
        );
        console.log("");

        (bool isPaused, string memory reason, uint64 since) = registry
            .pauseStatus();

        console.log(string.concat("System: ", isPaused ? "PAUSED" : "ACTIVE"));
        if (isPaused) {
            console.log(string.concat("  Reason: ", reason));
            console.log(string.concat("  Since: ", vm.toString(since)));
        }

        console.log("\n=============================\n");
    }

    function pauseAllAt(
        address registryAddr,
        address pegInAddr,
        address pegOutAddr,
        address collateralAddr,
        address discoveryAddr,
        string memory reason
    ) public {
        require(bytes(reason).length > 0, "Reason cannot be empty");

        console.log("\n=== PAUSE OPERATION ===\n");
        console.log(string.concat("Reason: ", reason));

        IPauseRegistry registry = IPauseRegistry(registryAddr);
        _verifyAllContractsUseRegistryAt(
            registry,
            pegInAddr,
            pegOutAddr,
            collateralAddr,
            discoveryAddr
        );

        vm.startBroadcast();
        registry.setPauseLevel(IPauseRegistry.PauseLevel.Soft, reason);
        vm.stopBroadcast();

        console.log(
            "  [OK] PauseRegistry paused - all Flyover contracts are now paused"
        );
        console.log("\n[SUCCESS] System paused successfully!");
    }

    function unpauseAllAt(
        address registryAddr,
        address pegInAddr,
        address pegOutAddr,
        address collateralAddr,
        address discoveryAddr
    ) public {
        console.log("\n=== UNPAUSE OPERATION ===\n");

        IPauseRegistry registry = IPauseRegistry(registryAddr);
        _verifyAllContractsUseRegistryAt(
            registry,
            pegInAddr,
            pegOutAddr,
            collateralAddr,
            discoveryAddr
        );

        vm.startBroadcast();
        registry.setPauseLevel(IPauseRegistry.PauseLevel.None, "");
        vm.stopBroadcast();

        console.log(
            "  [OK] PauseRegistry unpaused - all Flyover contracts are now active"
        );
        console.log("\n[SUCCESS] System unpaused successfully!");
    }
}

/**
 * @title PauseSystemTest
 * @notice Test for the pause-system task: registry verification and pause/unpause via script
 * @dev Uses mocks that expose pauseRegistry() and delegate pauseStatus() to the registry.
 *      Tests pass addresses explicitly (not via vm.setEnv) so they are safe under parallel execution.
 */
contract PauseSystemTest is Test {
    PauseSystemTestRunner public pauseScript;

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

        pauseScript = new PauseSystemTestRunner();
    }

    function _mockAddresses()
        internal
        view
        returns (
            address registry,
            address pegIn,
            address pegOut,
            address collateral,
            address discovery
        )
    {
        return (
            address(mockRegistry),
            address(mockPegIn),
            address(mockPegOut),
            address(mockCollateral),
            address(mockDiscovery)
        );
    }

    function test_CheckStatus() public {
        console.log("\n=== TEST CHECK STATUS ===\n");

        (bool r1, , ) = mockRegistry.pauseStatus();
        assertFalse(r1, "Registry should not be paused initially");

        (
            address registry,
            address pegIn,
            address pegOut,
            address collateral,
            address discovery
        ) = _mockAddresses();
        pauseScript.checkStatusAt(
            registry,
            pegIn,
            pegOut,
            collateral,
            discovery
        );

        mockRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Soft,
            "Test pause for status check"
        );

        (r1, , ) = mockRegistry.pauseStatus();
        assertTrue(r1, "Registry should be paused");

        pauseScript.checkStatusAt(
            registry,
            pegIn,
            pegOut,
            collateral,
            discovery
        );

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
        console.log("\n=== TEST COMPLETE PAUSE/UNPAUSE CYCLE ===\n");

        (
            address registry,
            address pegIn,
            address pegOut,
            address collateral,
            address discovery
        ) = _mockAddresses();

        console.log("1. Initial status check");
        pauseScript.checkStatusAt(
            registry,
            pegIn,
            pegOut,
            collateral,
            discovery
        );

        console.log("\n2. Pausing via registry");
        mockRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Soft,
            "Integration test"
        );

        console.log("\n3. Status while paused");
        pauseScript.checkStatusAt(
            registry,
            pegIn,
            pegOut,
            collateral,
            discovery
        );

        console.log("\n4. Unpausing registry");
        mockRegistry.setPauseLevel(IPauseRegistry.PauseLevel.None, "");

        console.log("\n5. Final status check");
        pauseScript.checkStatusAt(
            registry,
            pegIn,
            pegOut,
            collateral,
            discovery
        );

        console.log("\n[PASS] Complete cycle successful!");
    }

    function test_PauseAllViaScript() public {
        console.log("\n=== TEST PAUSE ALL VIA SCRIPT ===\n");

        (
            address registry,
            address pegIn,
            address pegOut,
            address collateral,
            address discovery
        ) = _mockAddresses();

        pauseScript.pauseAllAt(
            registry,
            pegIn,
            pegOut,
            collateral,
            discovery,
            "Script-initiated pause"
        );

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
        console.log("\n=== TEST UNPAUSE ALL VIA SCRIPT ===\n");

        (
            address registry,
            address pegIn,
            address pegOut,
            address collateral,
            address discovery
        ) = _mockAddresses();

        pauseScript.pauseAllAt(
            registry,
            pegIn,
            pegOut,
            collateral,
            discovery,
            "Pre-test pause"
        );
        pauseScript.unpauseAllAt(
            registry,
            pegIn,
            pegOut,
            collateral,
            discovery
        );

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
        MockPauseRegistry otherRegistry = new MockPauseRegistry();
        MockPausableContract mockWithOtherRegistry = new MockPausableContract(
            "Other",
            otherRegistry
        );

        (
            address registry,
            ,
            address pegOut,
            address collateral,
            address discovery
        ) = _mockAddresses();

        vm.expectRevert(
            "PauseSystem: PegInContract has different PauseRegistry"
        );
        pauseScript.checkStatusAt(
            registry,
            address(mockWithOtherRegistry),
            pegOut,
            collateral,
            discovery
        );
    }

    function test_RevertsWhenPegOutHasDifferentRegistry() public {
        MockPauseRegistry otherRegistry = new MockPauseRegistry();
        MockPausableContract mockWithOtherRegistry = new MockPausableContract(
            "Other",
            otherRegistry
        );

        (
            address registry,
            address pegIn,
            ,
            address collateral,
            address discovery
        ) = _mockAddresses();

        vm.expectRevert(
            "PauseSystem: PegOutContract has different PauseRegistry"
        );
        pauseScript.checkStatusAt(
            registry,
            pegIn,
            address(mockWithOtherRegistry),
            collateral,
            discovery
        );
    }

    function test_RevertsWhenCollateralHasDifferentRegistry() public {
        MockPauseRegistry otherRegistry = new MockPauseRegistry();
        MockPausableContract mockWithOtherRegistry = new MockPausableContract(
            "Other",
            otherRegistry
        );

        (
            address registry,
            address pegIn,
            address pegOut,
            ,
            address discovery
        ) = _mockAddresses();

        vm.expectRevert(
            "PauseSystem: CollateralManagement has different PauseRegistry"
        );
        pauseScript.checkStatusAt(
            registry,
            pegIn,
            pegOut,
            address(mockWithOtherRegistry),
            discovery
        );
    }

    function test_RevertsWhenDiscoveryHasDifferentRegistry() public {
        MockPauseRegistry otherRegistry = new MockPauseRegistry();
        MockPausableContract mockWithOtherRegistry = new MockPausableContract(
            "Other",
            otherRegistry
        );

        (
            address registry,
            address pegIn,
            address pegOut,
            address collateral,

        ) = _mockAddresses();

        vm.expectRevert(
            "PauseSystem: FlyoverDiscovery has different PauseRegistry"
        );
        pauseScript.checkStatusAt(
            registry,
            pegIn,
            pegOut,
            collateral,
            address(mockWithOtherRegistry)
        );
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
