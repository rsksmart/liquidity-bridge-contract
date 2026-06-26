// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {IFlyoverDiscovery} from "../../src/interfaces/IFlyoverDiscovery.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @title ActiveListingTest
/// @notice Tests for FlyoverDiscovery v2.1.0 active-provider indexing, initialization, and upgrade migration
contract ActiveListingTest is DiscoveryTestBase {
    // ============ Helpers ============

    function _registerAndApprove(
        address lp,
        string memory name,
        Flyover.ProviderType providerType,
        uint256 collateral
    ) internal returns (uint256 providerId) {
        vm.deal(lp, 100 ether);
        vm.prank(lp, lp);
        providerId = discovery.register{value: collateral}(
            name,
            "url",
            true,
            providerType
        );
        vm.prank(owner);
        discovery.approveRegistration(lp);
    }

    function _inflateLastProviderId(uint256 count) internal {
        for (uint256 i = 0; i < count; ++i) {
            address lp = makeAddr(string.concat("sybil", vm.toString(i)));
            vm.deal(lp, 100 ether);
            vm.prank(lp, lp);
            discovery.register{value: MIN_COLLATERAL}(
                "Pending",
                "url",
                true,
                Flyover.ProviderType.PegIn
            );
            vm.prank(lp);
            discovery.withdrawRegisterRequest();
        }
    }

    function _assertProvidersContain(address lp) internal view {
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        for (uint256 i = 0; i < providers.length; ++i) {
            if (providers[i].providerAddress == lp) return;
        }
        revert("Provider not listed");
    }

    function _assertProvidersExclude(address lp) internal view {
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        for (uint256 i = 0; i < providers.length; ++i) {
            if (providers[i].providerAddress == lp) {
                revert("Provider should not be listed");
            }
        }
    }

    function _clearActiveIndexFor(address lp) internal {
        vm.prank(address(collateralManagement));
        discovery.removeProvider(lp);
    }

    function _initializeV2_1_0() internal {
        vm.startPrank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));
        discovery.initializeV2_1_0();
        vm.stopPrank();
    }

    // ============ Functionality ============

    function test_RemoveProvider_RevertsWhenCallerIsNotCollateralManagement()
        public
    {
        deployDiscovery();
        setupProviders();

        vm.prank(pegInLp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.NotAuthorized.selector,
                pegInLp
            )
        );
        discovery.removeProvider(pegInLp);
    }

    function test_RemoveProvider_NoOpForZeroAndUnknownAddress() public {
        deployDiscovery();
        setupProviders();

        assertEq(discovery.getProviders().length, 3);

        vm.prank(address(collateralManagement));
        discovery.removeProvider(address(0));

        vm.prank(address(collateralManagement));
        discovery.removeProvider(makeAddr("unknown"));

        assertEq(discovery.getProviders().length, 3);
    }

    function test_RemoveProvider_IsIdempotent() public {
        deployDiscovery();
        setupProviders();

        assertEq(discovery.getProviders().length, 3);

        vm.startPrank(address(collateralManagement));
        discovery.removeProvider(pegInLp);
        discovery.removeProvider(pegInLp);
        vm.stopPrank();

        assertEq(discovery.getProviders().length, 2);
    }

    function test_ApproveRegistration_AddsProviderToActiveIndex() public {
        deployDiscovery();
        address lp = makeAddr("newLp");
        vm.deal(lp, 100 ether);

        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pending",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );
        assertEq(discovery.getProviders().length, 0);

        vm.prank(owner);
        discovery.approveRegistration(lp);

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 1);
        assertEq(providers[0].providerAddress, lp);
    }

    function test_ApproveRegistration_DoesNotDuplicateActiveIndexEntries()
        public
    {
        deployDiscoveryWithoutV2_1_0();
        vm.prank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));

        address lp = makeAddr("singleLp");
        _registerAndApprove(
            lp,
            "LP",
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );
        assertEq(discovery.getProviders().length, 1);

        _clearActiveIndexFor(lp);
        assertEq(discovery.getProviders().length, 0);

        vm.prank(owner);
        discovery.initializeV2_1_0();

        assertEq(discovery.getProviders().length, 1);
        _assertProvidersContain(lp);
    }

    function test_WithdrawCollateral_RemovesProviderFromListing() public {
        deployDiscovery();
        setupProviders();

        assertEq(discovery.getProviders().length, 3);

        vm.prank(pegInLp);
        collateralManagement.resign();
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        vm.prank(pegInLp);
        collateralManagement.withdrawCollateral();

        _assertProvidersExclude(pegInLp);
        assertEq(discovery.getProviders().length, 2);
    }

    function test_WithdrawAndReregister_RestoresProviderInListing() public {
        deployDiscovery();
        address lp = makeAddr("reregisterLp");
        _registerAndApprove(
            lp,
            "LP",
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );

        vm.prank(lp);
        collateralManagement.resign();
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);
        vm.prank(lp);
        collateralManagement.withdrawCollateral();
        _assertProvidersExclude(lp);

        _registerAndApprove(
            lp,
            "LP",
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );
        _assertProvidersContain(lp);
    }

    function test_DisabledProvider_ExcludedFromListingButRetainedInIndex()
        public
    {
        deployDiscovery();
        setupProviders();

        vm.prank(pegInLp);
        discovery.setProviderStatus(1, false);
        _assertProvidersExclude(pegInLp);

        vm.prank(pegInLp);
        discovery.setProviderStatus(1, true);
        _assertProvidersContain(pegInLp);
    }

    function test_ResignedProvider_ExcludedFromListingUntilWithdrawRemovesFromIndex()
        public
    {
        deployDiscovery();
        setupProviders();

        assertEq(discovery.getProviders().length, 3);

        vm.prank(pegInLp);
        collateralManagement.resign();
        _assertProvidersExclude(pegInLp);
        assertEq(discovery.getProviders().length, 2);

        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);
        vm.prank(pegInLp);
        collateralManagement.withdrawCollateral();
        _assertProvidersExclude(pegInLp);
        assertEq(discovery.getProviders().length, 2);
    }

    function test_WithdrawCollateral_SucceedsWhenFlyoverDiscoveryUnset()
        public
    {
        deployDiscoveryWithoutV2_1_0();
        address lp = makeAddr("unsetDiscoveryLp");
        _registerAndApprove(
            lp,
            "LP",
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );
        assertEq(discovery.getProviders().length, 1);

        vm.prank(lp);
        collateralManagement.resign();
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);

        vm.prank(lp);
        collateralManagement.withdrawCollateral();

        _assertProvidersExclude(lp);
    }

    // ============ Initialization — FlyoverDiscovery ============

    function test_InitializeV2_1_0_EmptyStateSucceeds() public {
        deployDiscoveryWithoutV2_1_0();

        vm.prank(owner);
        discovery.initializeV2_1_0();

        assertEq(discovery.getProviders().length, 0);
    }

    function test_InitializeV2_1_0_RevertsForNonAdmin() public {
        deployDiscoveryWithoutV2_1_0();
        address stranger = makeAddr("stranger");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                discovery.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(stranger);
        discovery.initializeV2_1_0();
    }

    function test_InitializeV2_1_0_CannotBeCalledTwice() public {
        deployDiscoveryWithoutV2_1_0();

        vm.startPrank(owner);
        discovery.initializeV2_1_0();
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        discovery.initializeV2_1_0();
        vm.stopPrank();
    }

    function test_InitializeV2_1_0_BackfillsRegisteredProviders() public {
        deployDiscoveryWithoutV2_1_0();
        vm.prank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));

        setupProviders();
        for (uint256 i = 0; i < 3; ++i) {
            address lp = i == 0 ? pegInLp : (i == 1 ? pegOutLp : fullLp);
            _clearActiveIndexFor(lp);
        }
        assertEq(discovery.getProviders().length, 0);

        vm.prank(owner);
        discovery.initializeV2_1_0();

        assertEq(discovery.getProviders().length, 3);
    }

    function test_InitializeV2_1_0_BackfillSetsApprovedRegistrationState()
        public
    {
        deployDiscoveryWithoutV2_1_0();
        vm.prank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));

        address lp = makeAddr("backfillLp");
        _registerAndApprove(
            lp,
            "LP",
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );
        _clearActiveIndexFor(lp);

        vm.prank(owner);
        discovery.initializeV2_1_0();

        assertEq(
            uint256(discovery.getRegistrationState(lp)),
            uint256(IFlyoverDiscovery.RegistrationState.Approved)
        );
        assertTrue(discovery.isOperational(Flyover.ProviderType.PegIn, lp));
        Flyover.LiquidityProvider memory lpRecord = discovery.getProvider(lp);
        assertEq(lpRecord.providerAddress, lp);
    }

    function test_InitializeV2_1_0_BackfillSkipsNonRegisteredProviders()
        public
    {
        deployDiscoveryWithoutV2_1_0();
        vm.prank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));

        address pendingLp = makeAddr("pendingLp");
        vm.deal(pendingLp, 100 ether);
        vm.prank(pendingLp, pendingLp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pending",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        address withdrawnLp = makeAddr("withdrawnLp");
        _registerAndApprove(
            withdrawnLp,
            "Withdrawn",
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );
        _clearActiveIndexFor(withdrawnLp);
        vm.prank(withdrawnLp);
        collateralManagement.resign();
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);
        vm.prank(withdrawnLp);
        collateralManagement.withdrawCollateral();

        address resignedLp = makeAddr("resignedLp");
        _registerAndApprove(
            resignedLp,
            "Resigned",
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );
        _clearActiveIndexFor(resignedLp);
        vm.prank(resignedLp);
        collateralManagement.resign();

        address keptLp = makeAddr("keptLp");
        _registerAndApprove(
            keptLp,
            "Kept",
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );
        _clearActiveIndexFor(keptLp);

        vm.prank(owner);
        discovery.initializeV2_1_0();

        assertEq(discovery.getProviders().length, 1);
        _assertProvidersContain(keptLp);
    }

    function test_InitializeV2_1_0_BackfillIgnoresInflatedLastProviderId()
        public
    {
        deployDiscoveryWithoutV2_1_0();
        vm.prank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));

        _inflateLastProviderId(5);
        address lp = makeAddr("realLp");
        _registerAndApprove(
            lp,
            "Real",
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );
        _clearActiveIndexFor(lp);

        assertEq(discovery.getProvidersId(), 6);

        vm.prank(owner);
        discovery.initializeV2_1_0();

        assertEq(discovery.getProviders().length, 1);
        _assertProvidersContain(lp);
    }

    // ============ Initialization — CollateralManagement ============

    function test_CollateralManagement_InitializeV2_1_0_WiresDiscoveryForWithdrawCallback()
        public
    {
        deployDiscoveryWithoutV2_1_0();
        address lp = makeAddr("wiredLp");
        _registerAndApprove(
            lp,
            "LP",
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );

        vm.prank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));

        vm.prank(lp);
        collateralManagement.resign();
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);
        vm.prank(lp);
        collateralManagement.withdrawCollateral();

        _assertProvidersExclude(lp);
    }

    function test_CollateralManagement_InitializeV2_1_0_RevertsForNonAdmin()
        public
    {
        deployDiscoveryWithoutV2_1_0();
        address stranger = makeAddr("stranger");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                collateralManagement.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(stranger);
        collateralManagement.initializeV2_1_0(address(discovery));
    }

    function test_CollateralManagement_InitializeV2_1_0_RevertsForInvalidAddress()
        public
    {
        deployDiscoveryWithoutV2_1_0();

        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.NoContract.selector, address(0))
        );
        collateralManagement.initializeV2_1_0(address(0));

        address eoa = makeAddr("eoa");
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.NoContract.selector, eoa)
        );
        collateralManagement.initializeV2_1_0(eoa);
        vm.stopPrank();
    }

    function test_CollateralManagement_InitializeV2_1_0_CannotBeCalledTwice()
        public
    {
        deployDiscoveryWithoutV2_1_0();

        vm.startPrank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        collateralManagement.initializeV2_1_0(address(discovery));
        vm.stopPrank();
    }

    function test_CollateralManagement_SetFlyoverDiscovery_UpdatesPointer()
        public
    {
        deployDiscoveryWithoutV2_1_0();
        CollateralManagementContract cm = collateralManagement;
        FlyoverDiscovery discoveryA = discovery;

        FlyoverDiscovery discoveryImpl = new FlyoverDiscovery();
        TransparentUpgradeableProxy discoveryBProxy = new TransparentUpgradeableProxy(
                address(discoveryImpl),
                owner,
                abi.encodeCall(
                    FlyoverDiscovery.initialize,
                    (owner, uint48(INITIAL_DELAY), address(cm), pauseRegistry)
                )
            );
        FlyoverDiscovery discoveryB = FlyoverDiscovery(
            payable(address(discoveryBProxy))
        );

        vm.startPrank(owner);
        cm.initializeV2_1_0(address(discoveryA));
        discoveryA.initializeV2_1_0();
        cm.grantRole(cm.COLLATERAL_ADDER(), address(discoveryB));
        cm.setFlyoverDiscovery(address(discoveryB));
        discoveryB.initializeV2_1_0();
        vm.stopPrank();

        address lp = makeAddr("pointerLp");
        vm.deal(lp, 100 ether);
        vm.prank(lp, lp);
        discoveryB.register{value: MIN_COLLATERAL}(
            "LP",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );
        vm.prank(owner);
        discoveryB.approveRegistration(lp);
        assertEq(discoveryB.getProviders().length, 1);

        vm.prank(lp);
        cm.resign();
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);
        vm.prank(lp);
        cm.withdrawCollateral();

        Flyover.LiquidityProvider[] memory providers = discoveryB
            .getProviders();
        assertEq(providers.length, 0);
    }

    // ============ Upgrade ============

    function test_Upgrade_PreMigrationListingEmptyWhenIndexCleared() public {
        deployDiscoveryWithoutV2_1_0();
        vm.prank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));

        setupProviders();
        for (uint256 i = 0; i < 3; ++i) {
            address lp = i == 0 ? pegInLp : (i == 1 ? pegOutLp : fullLp);
            _clearActiveIndexFor(lp);
        }

        assertTrue(
            collateralManagement.isRegistered(
                Flyover.ProviderType.PegIn,
                pegInLp
            )
        );
        assertEq(discovery.getProviders().length, 0);
    }

    function test_Upgrade_MigrationRestoresListing() public {
        deployDiscoveryWithoutV2_1_0();
        vm.prank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));

        setupProviders();
        for (uint256 i = 0; i < 3; ++i) {
            address lp = i == 0 ? pegInLp : (i == 1 ? pegOutLp : fullLp);
            _clearActiveIndexFor(lp);
        }

        upgradeDiscoveryContracts();

        vm.prank(owner);
        discovery.initializeV2_1_0();

        assertEq(discovery.getProviders().length, 3);
    }

    function test_Upgrade_BackfilledProvidersAreOperational() public {
        deployDiscoveryWithoutV2_1_0();
        vm.prank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));

        address lp = makeAddr("upgradeLp");
        _registerAndApprove(
            lp,
            "LP",
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );
        _clearActiveIndexFor(lp);

        upgradeDiscoveryContracts();

        vm.prank(owner);
        discovery.initializeV2_1_0();

        assertTrue(discovery.isOperational(Flyover.ProviderType.PegIn, lp));
        assertEq(discovery.getProvider(lp).providerAddress, lp);
    }

    function test_Upgrade_WithdrawStillRemovesFromListingAfterMigration()
        public
    {
        deployDiscoveryWithoutV2_1_0();
        vm.prank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));

        address lp = makeAddr("postUpgradeLp");
        _registerAndApprove(
            lp,
            "LP",
            Flyover.ProviderType.PegIn,
            MIN_COLLATERAL
        );
        _clearActiveIndexFor(lp);

        upgradeDiscoveryContracts();
        vm.prank(owner);
        discovery.initializeV2_1_0();
        _assertProvidersContain(lp);

        vm.prank(lp);
        collateralManagement.resign();
        vm.roll(block.number + TEST_RESIGN_DELAY_BLOCKS);
        vm.prank(lp);
        collateralManagement.withdrawCollateral();

        _assertProvidersExclude(lp);
    }

    function test_Upgrade_WithoutMigrationInitializerLeavesListingEmpty()
        public
    {
        deployDiscoveryWithoutV2_1_0();
        vm.prank(owner);
        collateralManagement.initializeV2_1_0(address(discovery));

        setupProviders();
        for (uint256 i = 0; i < 3; ++i) {
            address lp = i == 0 ? pegInLp : (i == 1 ? pegOutLp : fullLp);
            _clearActiveIndexFor(lp);
        }

        upgradeDiscoveryContracts();

        assertEq(discovery.getProviders().length, 0);
    }
}
