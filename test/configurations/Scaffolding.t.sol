// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title ScaffoldingTest
/// @notice Proxy/initialize wiring: init-once, admin role assignment, seed validation at init,
/// value rejection, and ERC-7201 storage namespace placement.
contract ScaffoldingTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function test_initializeOnce_reverts() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        config.initialize(
            owner,
            ADMIN_DELAY,
            TIMELOCK_DELAY,
            _seedConfig(),
            _boundsMin(),
            _boundsMax(),
            _seedPegOutConfig(),
            _pegOutBoundsMin(),
            _pegOutBoundsMax()
        );
    }

    function test_adminRoleAssigned() public view {
        assertTrue(config.hasRole(config.DEFAULT_ADMIN_ROLE(), owner));
        assertEq(config.defaultAdmin(), owner);
    }

    function test_strangerHasNoAdminRole() public view {
        assertFalse(config.hasRole(config.DEFAULT_ADMIN_ROLE(), stranger));
    }

    /// @notice The seed configuration must itself respect the deployment bounds.
    function test_initialize_seedOutOfBounds_reverts() public {
        FlyoverConfigurations impl = new FlyoverConfigurations();
        IFlyoverConfigurations.PegConfiguration memory badSeed = _seedConfig();
        badSeed.fixedFee = BOUND_MIN_FIXED_FEE - 1; // below the 2·D floor

        bytes memory initData = _initializeCall(
            badSeed,
            _boundsMin(),
            _boundsMax()
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.FixedFee,
                BOUND_MIN_FIXED_FEE - 1,
                BOUND_MIN_FIXED_FEE,
                BOUND_MAX_FIXED_FEE
            )
        );
        new ERC1967Proxy(address(impl), initData);
    }

    /// @notice An inverted seed bounds pair is rejected at initialization, so no code path can
    /// install bounds that admit no value at all.
    function test_initialize_invertedBounds_reverts() public {
        FlyoverConfigurations impl = new FlyoverConfigurations();
        IFlyoverConfigurations.PegConfiguration memory badMax = _boundsMax();
        badMax.fixedFee = BOUND_MIN_FIXED_FEE - 1;

        bytes memory initData = _initializeCall(
            _seedConfig(),
            _boundsMin(),
            badMax
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.InvalidBounds.selector,
                FlyoverConfigurations.Field.FixedFee,
                BOUND_MIN_FIXED_FEE,
                BOUND_MIN_FIXED_FEE - 1
            )
        );
        new ERC1967Proxy(address(impl), initData);
    }

    /// @notice Peg-in and peg-out are both live after the single initialize call.
    function test_initialize_seedsPegOut() public view {
        IFlyoverConfigurations.PegOutConfiguration memory active = config
            .getPegOutConfiguration();
        assertEq(active.fixedFee, SEED_FIXED_FEE);
        assertEq(active.penaltyFee, SEED_PENALTY_FEE);
        assertEq(active.claimWindow, SEED_CLAIM_WINDOW);
        (IFlyoverConfigurations.PegOutConfiguration memory minB, ) = config
            .getPegOutConfigurationBounds();
        assertEq(minB.penaltyFee, BOUND_MIN_PENALTY_FEE);
    }

    /// @notice A peg-out seed outside the deployment bounds is rejected from the proxy constructor.
    function test_initialize_pegOutSeedOutOfBounds_reverts() public {
        FlyoverConfigurations impl = new FlyoverConfigurations();
        IFlyoverConfigurations.PegOutConfiguration
            memory badSeed = _seedPegOutConfig();
        badSeed.penaltyFee = BOUND_MIN_PENALTY_FEE - 1;

        bytes memory initData = _initializeCall(
            _seedConfig(),
            _boundsMin(),
            _boundsMax(),
            badSeed,
            _pegOutBoundsMin(),
            _pegOutBoundsMax()
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.PenaltyFee,
                BOUND_MIN_PENALTY_FEE - 1,
                BOUND_MIN_PENALTY_FEE,
                BOUND_MAX_PENALTY_FEE
            )
        );
        new ERC1967Proxy(address(impl), initData);
    }

    /// @notice The contract does not accept plain value transfers.
    function test_receive_rejectsValue() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool ok, bytes memory ret) = address(config).call{value: 1}("");
        assertFalse(ok);
        assertEq(bytes4(ret), Flyover.PaymentNotAllowed.selector);
        assertEq(address(config).balance, 0);
    }

    /// @notice The first scalar of the mutable namespace (activePegIn.fixedFee) lives at the
    /// declared ERC-7201 base slot, proving namespace placement is correct.
    function test_storageSlot_matchesNamespace() public view {
        bytes32 raw = vm.load(address(config), STORAGE_SLOT);
        assertEq(uint256(raw), SEED_FIXED_FEE);
    }
}
