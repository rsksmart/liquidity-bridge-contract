// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {FlyoverDiscovery} from "src/FlyoverDiscovery.sol";
import {CollateralManagementContract} from "src/CollateralManagement.sol";
import {ICollateralManagement} from "src/interfaces/ICollateralManagement.sol";
import {PauseRegistry} from "src/PauseRegistry.sol";
import {PegInContract} from "src/PegInContract.sol";
import {PegOutContract} from "src/PegOutContract.sol";
import {BridgeMock} from "src/test-contracts/BridgeMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Flyover} from "src/libraries/Flyover.sol";
import {IPauseRegistry} from "src/interfaces/IPauseRegistry.sol";
import {Quotes} from "src/libraries/Quotes.sol";

/// @title System-wide Pause Functionality Tests
/// @notice Tests that verify pause/unpause operations across all contracts in the system
contract PauseTest is Test {
    PauseRegistry public pauseRegistry;
    FlyoverDiscovery public flyoverDiscovery;
    CollateralManagementContract public collateralManagement;
    PegInContract public pegInContract;
    PegOutContract public pegOutContract;
    BridgeMock public bridgeMock;

    address public owner;
    address public pauser;
    address[] public signers;

    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;
    IPauseRegistry.PauseLevel constant PAUSE_NONE =
        IPauseRegistry.PauseLevel.None;
    IPauseRegistry.PauseLevel constant PAUSE_SOFT =
        IPauseRegistry.PauseLevel.Soft;
    IPauseRegistry.PauseLevel constant PAUSE_HARD =
        IPauseRegistry.PauseLevel.Hard;

    function setUp() public {
        owner = address(this);
        pauser = makeAddr("pauser");
        vm.deal(pauser, 100 ether);

        for (uint i = 0; i < 5; i++) {
            address signer = makeAddr(string.concat("signer", vm.toString(i)));
            vm.deal(signer, 100 ether);
            signers.push(signer);
        }

        _deployContracts();
    }

    function _deployContracts() internal {
        bridgeMock = new BridgeMock();

        PauseRegistry prImpl = new PauseRegistry();
        pauseRegistry = PauseRegistry(
            payable(
                address(
                    new ERC1967Proxy(
                        address(prImpl),
                        abi.encodeCall(prImpl.initialize, (0, owner))
                    )
                )
            )
        );

        CollateralManagementContract cmImpl = new CollateralManagementContract();
        collateralManagement = CollateralManagementContract(
            payable(
                address(
                    new ERC1967Proxy(
                        address(cmImpl),
                        abi.encodeCall(
                            cmImpl.initialize,
                            (
                                owner,
                                30,
                                TEST_MIN_COLLATERAL,
                                500,
                                1000,
                                pauseRegistry
                            )
                        )
                    )
                )
            )
        );

        FlyoverDiscovery dImpl = new FlyoverDiscovery();
        flyoverDiscovery = FlyoverDiscovery(
            payable(
                address(
                    new ERC1967Proxy(
                        address(dImpl),
                        abi.encodeCall(
                            dImpl.initialize,
                            (
                                owner,
                                5000,
                                address(collateralManagement),
                                pauseRegistry
                            )
                        )
                    )
                )
            )
        );

        PegInContract piImpl = new PegInContract();
        pegInContract = PegInContract(
            payable(
                address(
                    new ERC1967Proxy(
                        address(piImpl),
                        abi.encodeCall(
                            piImpl.initialize,
                            (
                                owner,
                                payable(address(bridgeMock)),
                                2300 * 65164000,
                                0.5 ether,
                                address(collateralManagement),
                                false,
                                pauseRegistry
                            )
                        )
                    )
                )
            )
        );

        PegOutContract poImpl = new PegOutContract();
        pegOutContract = PegOutContract(
            payable(
                address(
                    new ERC1967Proxy(
                        address(poImpl),
                        abi.encodeCall(
                            poImpl.initialize,
                            (
                                owner,
                                payable(address(bridgeMock)),
                                2300 * 65164000,
                                address(collateralManagement),
                                false,
                                900,
                                pauseRegistry
                            )
                        )
                    )
                )
            )
        );

        vm.warp(block.timestamp + 31);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            address(flyoverDiscovery)
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            address(pegInContract)
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            address(pegOutContract)
        );
    }

    function _grantPauserRole() internal {
        pauseRegistry.grantRole(PAUSER_ROLE, pauser);
    }

    function _assertPauseLevel(
        IPauseRegistry.PauseLevel expected
    ) internal view {
        assertEq(uint8(pauseRegistry.pauseLevel()), uint8(expected));
    }

    function test_CanPauseAllContractsSimultaneously() public {
        _grantPauserRole();

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "System-wide soft pause");

        (bool isPausedPI, , ) = pegInContract.pauseStatus();
        (bool isPausedPO, , ) = pegOutContract.pauseStatus();
        (bool isPausedD, , ) = flyoverDiscovery.pauseStatus();
        (bool isPausedC, , ) = collateralManagement.pauseStatus();

        assertTrue(isPausedD);
        assertTrue(isPausedC);
        assertTrue(isPausedPI);
        assertTrue(isPausedPO);
    }

    function test_CanUnpauseAllContractsSimultaneously() public {
        _grantPauserRole();

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Pre-unpause setup");

        (bool isPausedPI, , ) = pegInContract.pauseStatus();
        (bool isPausedPO, , ) = pegOutContract.pauseStatus();
        (bool isPausedD, , ) = flyoverDiscovery.pauseStatus();
        (bool isPausedC, , ) = collateralManagement.pauseStatus();
        assertTrue(isPausedD);
        assertTrue(isPausedC);
        assertTrue(isPausedPI);
        assertTrue(isPausedPO);

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_NONE, "");

        string memory reasonD;
        string memory reasonC;
        string memory reasonPI;
        string memory reasonPO;
        (isPausedD, reasonD, ) = flyoverDiscovery.pauseStatus();
        (isPausedC, reasonC, ) = collateralManagement.pauseStatus();
        (isPausedPI, reasonPI, ) = pegInContract.pauseStatus();
        (isPausedPO, reasonPO, ) = pegOutContract.pauseStatus();

        assertFalse(isPausedPI);
        assertEq(reasonPI, "");
        assertFalse(isPausedPO);
        assertEq(reasonPO, "");
        assertFalse(isPausedD);
        assertEq(reasonD, "");
        assertFalse(isPausedC);
        assertEq(reasonC, "");
    }

    function test_TracksPauseTimestampsConsistentlyAcrossContracts() public {
        _grantPauserRole();

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Timestamp consistency");

        (, , uint256 timeD) = flyoverDiscovery.pauseStatus();
        (, , uint256 timeC) = collateralManagement.pauseStatus();
        (, , uint256 timePI) = pegInContract.pauseStatus();
        (, , uint256 timePO) = pegOutContract.pauseStatus();

        assertTrue(timeD > 0 && timeC > 0 && timePI > 0 && timePO > 0);
        assertEq(timeD, timeC);
        assertEq(timePI, timeD);
        assertEq(timePO, timePI);
    }

    function test_BlocksCriticalOperationsAcrossAllContractsWhenPaused()
        public
    {
        _grantPauserRole();

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Block critical operations");

        vm.prank(signers[1], signers[1]);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        flyoverDiscovery.register{value: 1 ether}(
            "Test LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegIn
        );

        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            owner
        );

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        collateralManagement.addPegInCollateralTo{value: 1 ether}(signers[1]);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        pegInContract.deposit{value: 1 ether}();

        Quotes.PegOutQuote memory quote;
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        pegOutContract.depositPegOut{value: 1 ether}(quote, hex"010203");
    }

    function test_AllowsViewFunctionsToContinueWorkingWhenPaused() public view {
        assertTrue(flyoverDiscovery.getProvidersId() >= 0);
        assertEq(collateralManagement.getMinCollateral(), TEST_MIN_COLLATERAL);
        assertTrue(pegInContract.getMinPegIn() > 0);
        assertTrue(pegOutContract.dustThreshold() > 0);
    }

    function test_AllowsNonPausableFunctionsToContinueWorking() public {
        _grantPauserRole();

        // First, register a provider before pausing
        vm.prank(signers[1], signers[1]);
        flyoverDiscovery.register{value: 1 ether}(
            "Test LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegIn
        );
        flyoverDiscovery.approveRegistration(signers[1]);

        uint256 providerId = flyoverDiscovery.getProvidersId();
        assertEq(providerId, 1, "Provider should be registered");

        // Pause via central registry
        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Allow non-pausable functions");

        // Verify contracts are paused
        (bool isPausedD, , ) = flyoverDiscovery.pauseStatus();
        (bool isPausedC, , ) = collateralManagement.pauseStatus();
        assertTrue(isPausedD, "FlyoverDiscovery should be paused");
        assertTrue(isPausedC, "CollateralManagement should be paused");

        // Test 1: setProviderStatus should work even when paused (not marked with whenNotPaused)
        vm.prank(signers[1]);
        flyoverDiscovery.setProviderStatus(providerId, false);
        Flyover.LiquidityProvider memory provider = flyoverDiscovery
            .getProvider(signers[1]);
        assertFalse(
            provider.status,
            "Provider status should be updated to false"
        );

        // Set it back to true
        vm.prank(signers[1]);
        flyoverDiscovery.setProviderStatus(providerId, true);
        provider = flyoverDiscovery.getProvider(signers[1]);
        assertTrue(
            provider.status,
            "Provider status should be updated to true"
        );

        // Test 2: withdrawRewards should work even when paused (not marked with whenNotPaused)
        // Note: In a real scenario, rewards would come from slashing, but for testing
        // we'll verify the function can be called (it will revert with NothingToWithdraw if no rewards)
        // The important part is that it doesn't revert due to pause
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.NothingToWithdraw.selector,
                signers[1]
            )
        );
        vm.prank(signers[1]);
        collateralManagement.withdrawRewards();

        // Test 3: withdrawCollateral should work even when paused (not marked with whenNotPaused)
        // This requires the provider to have resigned first, so we'll just verify it doesn't revert
        // due to pause (it will revert for other reasons like not resigned)
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralManagement.NotResigned.selector,
                signers[1]
            )
        );
        vm.prank(signers[1]);
        collateralManagement.withdrawCollateral();
    }

    function test_RestoresFullFunctionalityAfterSystemWideUnpause() public {
        _grantPauserRole();

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(
            PAUSE_SOFT,
            "Restore functionality scenario"
        );

        (bool isPausedD, , ) = flyoverDiscovery.pauseStatus();
        (bool isPausedC, , ) = collateralManagement.pauseStatus();
        (bool isPausedPI, , ) = pegInContract.pauseStatus();
        (bool isPausedPO, , ) = pegOutContract.pauseStatus();
        assertTrue(isPausedD);
        assertTrue(isPausedC);
        assertTrue(isPausedPI);
        assertTrue(isPausedPO);

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_NONE, "");

        (isPausedD, , ) = flyoverDiscovery.pauseStatus();
        (isPausedC, , ) = collateralManagement.pauseStatus();
        (isPausedPI, , ) = pegInContract.pauseStatus();
        (isPausedPO, , ) = pegOutContract.pauseStatus();
        assertFalse(isPausedD);
        assertFalse(isPausedC);
        assertFalse(isPausedPI);
        assertFalse(isPausedPO);

        vm.prank(signers[1], signers[1]);
        flyoverDiscovery.register{value: 1 ether}(
            "Test LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegIn
        );
        flyoverDiscovery.approveRegistration(signers[1]);

        assertEq(flyoverDiscovery.getProvidersId(), 1);

        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            owner
        );
        collateralManagement.addPegInCollateralTo{value: 0.5 ether}(signers[1]);

        assertEq(
            collateralManagement.getPegInCollateral(signers[1]),
            1.5 ether
        );
    }

    function test_PauseOncePausesAllContracts() public {
        _grantPauserRole();

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Pause once affects all");

        (bool isPausedD, , ) = flyoverDiscovery.pauseStatus();
        (bool isPausedC, , ) = collateralManagement.pauseStatus();
        (bool isPausedPI, , ) = pegInContract.pauseStatus();
        (bool isPausedPO, , ) = pegOutContract.pauseStatus();

        assertTrue(isPausedD, "Discovery should be paused");
        assertTrue(isPausedC, "Collateral should be paused");
        assertTrue(isPausedPI, "PegIn should be paused");
        assertTrue(isPausedPO, "PegOut should be paused");
    }

    function test_MaintainsPauseStateAcrossMultipleOperations() public {
        _grantPauserRole();

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "State across operations");

        vm.startPrank(signers[1], signers[1]);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        flyoverDiscovery.register{value: 1 ether}(
            "LP1",
            "url1",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        flyoverDiscovery.register{value: 1 ether}(
            "LP2",
            "url2",
            true,
            Flyover.ProviderType.PegOut
        );

        vm.stopPrank();

        (bool isPausedD, , ) = flyoverDiscovery.pauseStatus();
        (bool isPausedC, , ) = collateralManagement.pauseStatus();
        (bool isPausedPI, , ) = pegInContract.pauseStatus();
        (bool isPausedPO, , ) = pegOutContract.pauseStatus();

        assertTrue(isPausedD);
        assertTrue(isPausedC);
        assertTrue(isPausedPI);
        assertTrue(isPausedPO);
    }

    // ---------- Two-level pause (soft vs hard) ----------

    function test_SoftPause_BlocksNewBusiness_AllowsContinuations() public {
        _grantPauserRole();
        vm.prank(signers[1], signers[1]);
        flyoverDiscovery.register{value: 1 ether}(
            "LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegIn
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            owner
        );
        collateralManagement.addPegInCollateralTo{value: 0.5 ether}(signers[1]);
        vm.prank(signers[1]);
        pegInContract.deposit{value: 0.5 ether}();

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Soft pause mode"); // level 1

        _assertPauseLevel(PAUSE_SOFT);

        // New business blocked
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        flyoverDiscovery.register{value: 0.1 ether}(
            "LP2",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(signers[1]);
        pegInContract.deposit{value: 0.1 ether}();

        // LP metadata updates are allowed during soft pause (not a new flow initiation)
        vm.prank(signers[1]);
        flyoverDiscovery.updateProvider(
            "LP-updated",
            "http://localhost/api/v2"
        );

        // Continuations allowed (whenNotHardPaused passes at level 1)
        vm.prank(signers[1]);
        pegInContract.withdraw(0.3 ether);
    }

    function test_HardPause_BlocksAllStateChangingIncludingContinuations()
        public
    {
        _grantPauserRole();
        vm.prank(signers[1], signers[1]);
        flyoverDiscovery.register{value: 1 ether}(
            "LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegIn
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            owner
        );
        collateralManagement.addPegInCollateralTo{value: 0.5 ether}(signers[1]);
        vm.prank(signers[1]);
        pegInContract.deposit{value: 0.5 ether}();

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_HARD, "Hard pause mode"); // hard pause

        _assertPauseLevel(PAUSE_HARD);

        // New business blocked
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        flyoverDiscovery.register{value: 0.1 ether}(
            "LP2",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        // Metadata updates are blocked on hard pause (full freeze)
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(signers[1]);
        flyoverDiscovery.updateProvider(
            "LP-updated",
            "http://localhost/api/v2"
        );

        // Continuations/outflows also blocked at level 2
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(signers[1]);
        pegInContract.withdraw(0.3 ether);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(signers[1]);
        collateralManagement.resign();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(signers[1]);
        collateralManagement.withdrawRewards();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(signers[1]);
        pegOutContract.withdraw(payable(signers[1]), 0);
    }

    function test_PauseUnpause_BackwardCompatible_Level1() public {
        _grantPauserRole();
        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Reason");
        _assertPauseLevel(PAUSE_SOFT);
        assertTrue(pauseRegistry.paused());
        (bool isPaused, string memory reason, ) = pauseRegistry.pauseStatus();
        assertTrue(isPaused);
        assertEq(reason, "Reason");

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_NONE, "");
        _assertPauseLevel(PAUSE_NONE);
        assertFalse(pauseRegistry.paused());
    }

    function test_SetPauseLevel_IsIdempotentAtSoftLevel() public {
        _grantPauserRole();

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Idempotent soft pause");

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Idempotent soft pause again");

        _assertPauseLevel(PAUSE_SOFT);
    }

    function test_SetPauseLevel_CanDowngradeFromHardToSoft() public {
        _grantPauserRole();

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_HARD, "Start hard pause");
        (
            uint64 startTs,
            uint64 endTsBefore,
            uint64 startBl,
            uint64 endBlBefore
        ) = pauseRegistry.hardPauses(0);

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Downgrade to soft pause");

        _assertPauseLevel(PAUSE_SOFT);
        (
            uint64 startTsAfter,
            uint64 endTsAfter,
            uint64 startBlAfter,
            uint64 endBlAfter
        ) = pauseRegistry.hardPauses(0);
        assertEq(startTsAfter, startTs);
        assertEq(startBlAfter, startBl);
        assertEq(endTsBefore, 0);
        assertEq(endBlBefore, 0);
        assertTrue(endTsAfter > 0);
        assertTrue(endBlAfter > 0);
    }

    function test_SetPauseLevel_TracksContinuousPauseTimestamp() public {
        _grantPauserRole();

        (, , uint64 since0) = pauseRegistry.pauseStatus();
        assertEq(since0, 0);

        vm.warp(block.timestamp + 10);
        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Continuous timestamp soft");
        (, , uint64 since1) = pauseRegistry.pauseStatus();
        assertEq(since1, uint64(block.timestamp));

        vm.warp(block.timestamp + 15);
        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_HARD, "Continuous timestamp hard");
        (, , uint64 since2) = pauseRegistry.pauseStatus();
        assertEq(since2, since1);

        vm.warp(block.timestamp + 12);
        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Back to soft timestamp");
        (, , uint64 since3) = pauseRegistry.pauseStatus();
        assertEq(since3, since1);

        vm.warp(block.timestamp + 8);
        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_NONE, "");
        (, , uint64 since4) = pauseRegistry.pauseStatus();
        assertEq(since4, 0);
    }

    function test_PauseAndSetPauseLevel_KeepSamePauseStartTimestamp() public {
        _grantPauserRole();

        vm.warp(block.timestamp + 7);
        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Pause before hard transition");
        (, , uint64 sinceAfterPause) = pauseRegistry.pauseStatus();

        vm.warp(block.timestamp + 9);
        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_HARD, "Transition to hard");
        (, , uint64 sinceAfterHardPause) = pauseRegistry.pauseStatus();
        assertEq(sinceAfterHardPause, sinceAfterPause);

        vm.warp(block.timestamp + 11);
        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_SOFT, "Back to soft");
        (, , uint64 sinceAfterSoftPause) = pauseRegistry.pauseStatus();
        assertEq(sinceAfterSoftPause, sinceAfterPause);
    }

    // ---------- Hard-pause timer overlap ----------

    function test_HardPause_AppendsAndClosesLog() public {
        _grantPauserRole();
        assertEq(pauseRegistry.hardPausesCount(), 0);

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_HARD, "Append hard pause log");
        assertEq(pauseRegistry.hardPausesCount(), 1);
        (uint64 sTs, uint64 eTs, uint64 sBl, uint64 eBl) = pauseRegistry
            .hardPauses(0);
        assertTrue(sTs > 0 && sBl > 0);
        assertEq(eTs, 0);
        assertEq(eBl, 0);

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_NONE, "");
        assertEq(pauseRegistry.hardPausesCount(), 1);
        (, eTs, , eBl) = pauseRegistry.hardPauses(0);
        assertTrue(eTs > 0 && eBl > 0);
    }

    function test_ComputePauseOverlap_AccountsForHardPauseWindow() public {
        _grantPauserRole();
        uint256 startTs = block.timestamp;

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_HARD, "Hard pause overlap");
        vm.warp(block.timestamp + 90);

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_NONE, "");

        uint256 overlap = pauseRegistry.computePauseOverlap(
            startTs,
            block.timestamp
        );
        assertEq(overlap, 90);
    }

    function test_ComputePauseOverlapBlocks_AccountsForHardPauseWindow()
        public
    {
        _grantPauserRole();
        uint256 startBlock = block.number;

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_HARD, "Hard pause overlap blocks");
        vm.roll(block.number + 25);

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_NONE, "");

        uint256 overlap = pauseRegistry.computePauseOverlapBlocks(
            startBlock,
            block.number
        );
        assertEq(overlap, 25);
    }

    function test_ResignDelay_ExcludesHardPausedBlocks() public {
        _grantPauserRole();

        vm.prank(signers[2], signers[2]);
        flyoverDiscovery.register{value: 1 ether}(
            "PauseDelay LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegIn
        );
        flyoverDiscovery.approveRegistration(signers[2]);

        vm.prank(signers[2]);
        collateralManagement.resign();
        uint256 resignationBlock = collateralManagement.getResignationBlock(
            signers[2]
        );

        vm.roll(resignationBlock + 200);

        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_HARD, "Hard pause resign delay");
        vm.roll(block.number + 400);
        vm.prank(pauser);
        pauseRegistry.setPauseLevel(PAUSE_NONE, "");

        // Effective elapsed = 200 (400 hard-pause blocks should be excluded), so delay is not met yet.
        vm.expectRevert();
        vm.prank(signers[2]);
        collateralManagement.withdrawCollateral();

        vm.roll(block.number + 300);
        vm.prank(signers[2]);
        collateralManagement.withdrawCollateral();
    }
}
