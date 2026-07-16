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
        vm.expectRevert(); // Initializable: InvalidInitialization
        config.initialize(owner, ADMIN_DELAY, TIMELOCK_DELAY, _seedConfig(), _boundsMin(), _boundsMax());
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

        bytes memory initData = abi.encodeCall(
            FlyoverConfigurations.initialize,
            (owner, ADMIN_DELAY, TIMELOCK_DELAY, badSeed, _boundsMin(), _boundsMax())
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
