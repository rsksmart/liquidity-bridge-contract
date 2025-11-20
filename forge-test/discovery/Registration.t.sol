// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {IFlyoverDiscovery} from "../../contracts/interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";
import {RegisterCaller} from "../../contracts/test/RegisterCaller.sol";

contract RegistrationTest is DiscoveryTestBase {
    function setUp() public {
        deployDiscovery();
    }

    // ============ Registration tests ============

    function test_Register_RegistersProvidersAndIncrementsLastProviderId()
        public
    {
        address lp1 = makeAddr("lp1");
        address lp2 = makeAddr("lp2");
        address lp3 = makeAddr("lp3");

        vm.deal(lp1, 100 ether);
        vm.deal(lp2, 100 ether);
        vm.deal(lp3, 100 ether);

        // Register LP1
        vm.prank(lp1);
        vm.expectEmit(true, true, true, true);
        emit IFlyoverDiscovery.Register(1, lp1, MIN_COLLATERAL * 2);
        discovery.register{value: MIN_COLLATERAL * 2}(
            "LP1",
            "http://localhost/api1",
            true,
            Flyover.ProviderType.Both
        );

        // Register LP2
        vm.prank(lp2);
        vm.expectEmit(true, true, true, true);
        emit IFlyoverDiscovery.Register(2, lp2, MIN_COLLATERAL);
        discovery.register{value: MIN_COLLATERAL}(
            "LP2",
            "http://localhost/api2",
            true,
            Flyover.ProviderType.PegIn
        );

        // Register LP3
        vm.prank(lp3);
        vm.expectEmit(true, true, true, true);
        emit IFlyoverDiscovery.Register(3, lp3, MIN_COLLATERAL);
        discovery.register{value: MIN_COLLATERAL}(
            "LP3",
            "http://localhost/api3",
            true,
            Flyover.ProviderType.PegOut
        );

        uint256 lastId = discovery.getProvidersId();
        assertEq(lastId, 3, "Last provider ID should be 3");
    }

    function test_Register_RevertsOnInvalidRegistrationData() public {
        address lp = makeAddr("lp");
        vm.deal(lp, 100 ether);

        // Empty name
        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.InvalidProviderData.selector,
                "",
                "http://localhost/api"
            )
        );
        discovery.register{value: MIN_COLLATERAL}(
            "",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegIn
        );

        // Empty URL
        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.InvalidProviderData.selector,
                "LP",
                ""
            )
        );
        discovery.register{value: MIN_COLLATERAL}(
            "LP",
            "",
            true,
            Flyover.ProviderType.PegIn
        );
    }

    function test_Register_RevertsOnInsufficientCollateralDependingOnProviderType()
        public
    {
        address lpBoth = makeAddr("lpBoth");
        address lpIn = makeAddr("lpIn");
        address lpOut = makeAddr("lpOut");

        vm.deal(lpBoth, 100 ether);
        vm.deal(lpIn, 100 ether);
        vm.deal(lpOut, 100 ether);

        // Both type needs 2x MIN_COLLATERAL
        vm.prank(lpBoth);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.InsufficientCollateral.selector,
                MIN_COLLATERAL
            )
        );
        discovery.register{value: MIN_COLLATERAL}(
            "LPB",
            "url",
            true,
            Flyover.ProviderType.Both
        );

        // PegIn with insufficient collateral
        vm.prank(lpIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.InsufficientCollateral.selector,
                MIN_COLLATERAL - 1
            )
        );
        discovery.register{value: MIN_COLLATERAL - 1}(
            "LPI",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        // PegOut with insufficient collateral
        vm.prank(lpOut);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.InsufficientCollateral.selector,
                MIN_COLLATERAL - 1
            )
        );
        discovery.register{value: MIN_COLLATERAL - 1}(
            "LPO",
            "url",
            true,
            Flyover.ProviderType.PegOut
        );
    }

    function test_Register_ReturnsLastProviderIdAfterPreRegisteredProviders()
        public
    {
        setupProviders();

        uint256 lastId = discovery.getProvidersId();
        assertEq(lastId, 3, "Last provider ID should be 3");
    }

    // ============ Registration edge cases tests ============

    function test_Register_RevertsWhenProviderTypeIsInvalid() public {
        RegisterCaller caller = new RegisterCaller();
        vm.deal(address(caller), 100 ether);

        // Note: With the current function signature (enum parameter), the ABI decoder
        // reverts with panic 0x21 for values outside the enum before the function body
        // executes, so the contract's InvalidProviderType custom error cannot be reached.
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x21));
        caller.callRegisterWithTypeUint{value: MIN_COLLATERAL}(
            address(discovery),
            "N",
            "U",
            true,
            999
        );
    }

    function test_Register_PreventsMultipleRegistrationsBySameEOA() public {
        address lp = makeAddr("lp");
        vm.deal(lp, 100 ether);

        // First registration succeeds
        vm.prank(lp);
        discovery.register{value: MIN_COLLATERAL}(
            "N1",
            "U1",
            true,
            Flyover.ProviderType.PegIn
        );

        // Second registration by the same EOA should fail
        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.AlreadyRegistered.selector,
                lp
            )
        );
        discovery.register{value: MIN_COLLATERAL}(
            "N2",
            "U2",
            true,
            Flyover.ProviderType.PegOut
        );

        // Verify only 1 provider exists
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 1, "Should have 1 provider");
        assertEq(
            providers[0].providerAddress,
            lp,
            "Provider address should match"
        );
    }
}
