// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {IFlyoverDiscovery} from "../../src/interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {RegisterCaller} from "../../src/test/RegisterCaller.sol";

contract NotEoaTest is DiscoveryTestBase {
    function setUp() public {
        deployDiscovery();
    }

    // ============ NotEOA checks tests ============

    function test_Register_RevertsWhenContractCallsRegister() public {
        RegisterCaller caller = new RegisterCaller();
        vm.deal(address(caller), 100 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.NotEOA.selector,
                address(caller)
            )
        );
        caller.callRegister{value: MIN_COLLATERAL}(
            address(discovery),
            "N",
            "U",
            true,
            Flyover.ProviderType.PegIn
        );
    }

    function test_Register_RevertsWhenContractCallsRegisterWithLowCollateral()
        public
    {
        RegisterCaller caller = new RegisterCaller();
        vm.deal(address(caller), 100 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.NotEOA.selector,
                address(caller)
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

    function test_Register_RevertsWhenMsgSenderDiffersFromTxOrigin() public {
        address sender = makeAddr("sender");
        address origin = makeAddr("origin");
        vm.deal(sender, 100 ether);

        vm.prank(sender, origin);
        vm.expectRevert(
            abi.encodeWithSelector(IFlyoverDiscovery.NotEOA.selector, sender)
        );
        discovery.register{value: MIN_COLLATERAL}(
            "N",
            "U",
            true,
            Flyover.ProviderType.PegIn
        );
    }
}
