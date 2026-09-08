// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfigurationsTestBase} from "./ConfigurationsTestBase.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title RegistrantFeeTest
contract RegistrantFeeTest is ConfigurationsTestBase {
    function setUp() public {
        _deploy();
    }

    function test_seed_registrantFee_is_accepted() public view {
        assertEq(
            config.getPegInConfiguration().registrantFee,
            SEED_REGISTRANT_FEE
        );
    }

    function test_queueChange_rejects_registrantFee_at_cap() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.registrantFee = 0.001 ether;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations.ConfigValueOutOfBounds.selector,
                FlyoverConfigurations.Field.RegistrantFee,
                0.001 ether,
                BOUND_MIN_REGISTRANT_FEE,
                BOUND_MAX_REGISTRANT_FEE
            )
        );
        config.queueChange(c);
    }

    function test_queueChange_rejects_fixedFee_below_registrantFee() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.registrantFee = c.fixedFee + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlyoverConfigurations
                    .InsufficientFixedFeeForRegistrant
                    .selector,
                c.fixedFee,
                c.registrantFee,
                uint256(0)
            )
        );
        config.queueChange(c);
    }

    function test_queueChange_accepts_valid_registrantFee() public {
        IFlyoverConfigurations.PegConfiguration memory c = _altConfig();
        c.fixedFee = SEED_REGISTRANT_FEE;
        c.registrantFee = SEED_REGISTRANT_FEE;
        vm.prank(owner);
        config.queueChange(c);
        (IFlyoverConfigurations.PegConfiguration memory pending, ) = config
            .getPendingChange();
        assertEq(pending.registrantFee, SEED_REGISTRANT_FEE);
    }
}
