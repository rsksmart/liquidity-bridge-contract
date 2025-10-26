// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {IFlyoverDiscovery} from "../../contracts/interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";
import {RegisterCaller} from "../../contracts/test/RegisterCaller.sol";

contract NotEoaTest is DiscoveryTestBase {
    function setUp() public {
        deployDiscovery();
    }

    // ============ NotEOA checks tests ============

    function test_Register_RevertsWhenContractCallsRegister() public {
        RegisterCaller caller = new RegisterCaller();

        vm.expectRevert(
            abi.encodeWithSelector(IFlyoverDiscovery.NotEOA.selector, address(caller))
        );
        caller.callRegister{value: MIN_COLLATERAL}(
            address(discovery),
            "N",
            "U",
            true,
            Flyover.ProviderType.PegIn
        );
    }
}
