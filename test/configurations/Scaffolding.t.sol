// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @notice Scaffolding: init-once, admin role, and ERC-7201 storage namespace placement.
contract ScaffoldingTest is ConfigurationsTestBase {
    // keccak256(abi.encode(uint256(keccak256("rsk.flyover.FlyoverConfigurations")) - 1)) & ~0xff
    bytes32 internal constant STORAGE_SLOT =
        0x13aa2a37a5354fe7c5dcced2a6c33933ec66091f98f22792660cd2862f158700;

    function setUp() public {
        _deploy();
    }

    function test_initializeOnce_reverts() public {
        (
            IFlyoverConfigurations.PegConfiguration memory pegIn,
            IFlyoverConfigurations.PegConfiguration memory pegOut
        ) = _seedConfigs();
        (
            IFlyoverConfigurations.PegConfiguration memory min,
            IFlyoverConfigurations.PegConfiguration memory max
        ) = _bounds();

        vm.expectRevert(); // InvalidInitialization
        config.initialize(owner, ADMIN_DELAY, TIMELOCK_DELAY, pegIn, pegOut, min, max, min, max);
    }

    function test_adminRoleAssigned() public view {
        assertTrue(config.hasRole(config.DEFAULT_ADMIN_ROLE(), owner));
    }

    function test_storageSlot_matchesNamespace() public view {
        // The first scalar of the main namespace struct is pegIn.fixedFee. It must live at the
        // declared ERC-7201 slot, proving the namespace placement is correct.
        bytes32 raw = vm.load(address(config), STORAGE_SLOT);
        assertEq(uint256(raw), 1000 * SAT);
    }

    function test_initInvariant_seedRespectsExpireAfterCall() public view {
        IFlyoverConfigurations.PegConfiguration memory c = config.getPegInConfiguration();
        assertTrue(c.expireTime > c.callTime);
    }
}
