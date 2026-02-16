// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {IFlyoverDiscovery} from "../../src/interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {RegisterCaller} from "../../src/test/RegisterCaller.sol";

contract ContractCallerRegistrationTest is DiscoveryTestBase {
    function setUp() public {
        deployDiscovery();
    }

    // ============ Contract caller registration tests ============

    function test_Register_AllowsContractCallsRegister() public {
        RegisterCaller caller = new RegisterCaller();
        vm.deal(address(caller), 100 ether);

        caller.callRegister{value: MIN_COLLATERAL}(
            address(discovery),
            "N",
            "U",
            true,
            Flyover.ProviderType.PegIn
        );

        Flyover.LiquidityProvider memory provider = discovery.getProvider(
            address(caller)
        );
        assertEq(provider.id, 1, "Provider id should be 1");
        assertEq(
            provider.providerAddress,
            address(caller),
            "Provider address should be the caller contract"
        );
    }

    function test_Register_RevertsWhenContractProvidesInsufficientCollateral()
        public
    {
        RegisterCaller caller = new RegisterCaller();
        vm.deal(address(caller), 100 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.InsufficientCollateral.selector,
                MIN_COLLATERAL - 1
            )
        );
        caller.callRegister{value: MIN_COLLATERAL - 1}(
            address(discovery),
            "N",
            "U",
            true,
            Flyover.ProviderType.PegIn
        );
    }
}
