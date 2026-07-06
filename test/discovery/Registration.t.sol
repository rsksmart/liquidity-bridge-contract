// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryTestBase} from "./DiscoveryTestBase.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {IFlyoverDiscovery} from "../../src/interfaces/IFlyoverDiscovery.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {RegisterCaller} from "../../src/test/RegisterCaller.sol";

contract RegistrationTest is DiscoveryTestBase {
    function setUp() public {
        deployDiscovery();
    }

    // ============ Registration tests ============

    function test_Initialize_RevertsWhenCalledOnImplementation() public {
        FlyoverDiscovery implementation = new FlyoverDiscovery();

        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        implementation.initialize(
            owner,
            0,
            address(collateralManagement),
            pauseRegistry
        );
    }

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
        vm.prank(lp1, lp1);
        vm.expectEmit(true, true, true, true);
        emit IFlyoverDiscovery.Register(1, lp1, MIN_COLLATERAL * 2);
        discovery.register{value: MIN_COLLATERAL * 2}(
            "LP1",
            "http://localhost/api1",
            true,
            Flyover.ProviderType.Both
        );

        // Register LP2
        vm.prank(lp2, lp2);
        vm.expectEmit(true, true, true, true);
        emit IFlyoverDiscovery.Register(2, lp2, MIN_COLLATERAL);
        discovery.register{value: MIN_COLLATERAL}(
            "LP2",
            "http://localhost/api2",
            true,
            Flyover.ProviderType.PegIn
        );

        // Register LP3
        vm.prank(lp3, lp3);
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
        vm.prank(lp, lp);
        vm.expectRevert(
            providerDataLengthOutOfBoundsData(
                0,
                bytes("http://localhost/api").length
            )
        );
        discovery.register{value: MIN_COLLATERAL}(
            "",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegIn
        );

        // Empty URL
        vm.prank(lp, lp);
        vm.expectRevert(
            providerDataLengthOutOfBoundsData(bytes("LP").length, 0)
        );
        discovery.register{value: MIN_COLLATERAL}(
            "LP",
            "",
            true,
            Flyover.ProviderType.PegIn
        );
    }

    function test_Register_RevertsWhenProviderNameExceedsMaxLength() public {
        address lp = makeAddr("lpLongName");
        vm.deal(lp, 100 ether);

        string memory tooLongName = makeStringOfLength(
            MAX_PROVIDER_NAME_LENGTH + 1
        );
        string memory validUrl = "u";

        vm.prank(lp, lp);
        vm.expectRevert(
            providerDataLengthOutOfBoundsData(
                MAX_PROVIDER_NAME_LENGTH + 1,
                bytes(validUrl).length
            )
        );
        discovery.register{value: MIN_COLLATERAL}(
            tooLongName,
            validUrl,
            true,
            Flyover.ProviderType.PegIn
        );
    }

    function test_Register_RevertsWhenProviderApiBaseUrlExceedsMaxLength()
        public
    {
        address lp = makeAddr("lpLongUrl");
        vm.deal(lp, 100 ether);

        string memory validName = "n";
        string memory tooLongUrl = makeStringOfLength(
            MAX_PROVIDER_API_BASE_URL_LENGTH + 1
        );

        vm.prank(lp, lp);
        vm.expectRevert(
            providerDataLengthOutOfBoundsData(
                bytes(validName).length,
                MAX_PROVIDER_API_BASE_URL_LENGTH + 1
            )
        );
        discovery.register{value: MIN_COLLATERAL}(
            validName,
            tooLongUrl,
            true,
            Flyover.ProviderType.PegIn
        );
    }

    function test_Register_AcceptsProviderDataAtMaxLength() public {
        address lp = makeAddr("lpMaxLen");
        vm.deal(lp, 100 ether);

        string memory name = makeStringOfLength(MAX_PROVIDER_NAME_LENGTH);
        string memory url = makeStringOfLength(
            MAX_PROVIDER_API_BASE_URL_LENGTH
        );

        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            name,
            url,
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(owner);
        discovery.approveRegistration(lp);

        Flyover.LiquidityProvider memory p = discovery.getProvider(lp);
        assertEq(bytes(p.name).length, MAX_PROVIDER_NAME_LENGTH);
        assertEq(bytes(p.apiBaseUrl).length, MAX_PROVIDER_API_BASE_URL_LENGTH);
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
        vm.prank(lpBoth, lpBoth);
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
        vm.prank(lpIn, lpIn);
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
        vm.prank(lpOut, lpOut);
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
        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "N1",
            "U1",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(owner);
        discovery.approveRegistration(lp);

        // Second registration by the same EOA should fail
        vm.prank(lp, lp);
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

        // Verify only 1 approved provider exists
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 1, "Should have 1 provider");
        assertEq(
            providers[0].providerAddress,
            lp,
            "Provider address should match"
        );
    }

    function test_Register_CreatesPendingRequestWithoutListingProvider()
        public
    {
        address lp = makeAddr("lpPending");
        vm.deal(lp, 100 ether);

        vm.prank(lp, lp);
        uint256 id = discovery.register{value: MIN_COLLATERAL}(
            "Pending",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );
        assertEq(id, 1, "Expected provider id 1");

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 0, "Pending provider should not be listed");
        assertEq(
            collateralManagement.getPegInCollateral(lp),
            0,
            "Collateral should not be forwarded before approval"
        );

        vm.expectRevert(
            abi.encodeWithSelector(Flyover.ProviderNotRegistered.selector, lp)
        );
        discovery.getProvider(lp);
    }

    function test_ApproveRegistration_ListsProviderAndForwardsCollateral()
        public
    {
        address lp = makeAddr("lpApprove");
        vm.deal(lp, 100 ether);

        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pending",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(owner);
        discovery.approveRegistration(lp);

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 1, "Approved provider should be listed");
        assertEq(
            collateralManagement.getPegInCollateral(lp),
            MIN_COLLATERAL,
            "Collateral should be forwarded on approval"
        );
    }

    function test_RejectRegistration_RefundsCollateral() public {
        address lp = makeAddr("lpReject");
        vm.deal(lp, 100 ether);
        uint256 startBalance = lp.balance;

        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pending",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(owner);
        discovery.rejectRegistration(lp);

        assertEq(
            uint8(discovery.getRegistrationState(lp)),
            uint8(IFlyoverDiscovery.RegistrationState.Rejected),
            "State should be Rejected after rejection"
        );

        assertEq(lp.balance, startBalance, "Collateral should be refunded");
        assertEq(collateralManagement.getPegInCollateral(lp), 0);

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 0, "Rejected provider should not be listed");
    }

    function test_WithdrawRegisterRequest_RefundsCollateral() public {
        address lp = makeAddr("lpWithdraw");
        vm.deal(lp, 100 ether);
        uint256 startBalance = lp.balance;

        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pending",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(lp);
        discovery.withdrawRegisterRequest();

        assertEq(
            uint8(discovery.getRegistrationState(lp)),
            uint8(IFlyoverDiscovery.RegistrationState.Withdrawn),
            "State should be Withdrawn after withdrawal"
        );

        assertEq(lp.balance, startBalance, "Collateral should be refunded");
        assertEq(collateralManagement.getPegInCollateral(lp), 0);
    }

    function test_WithdrawRegisterRequest_AllowsRefundDuringSoftPause() public {
        address lp = makeAddr("lpWithdrawSoftPause");
        vm.deal(lp, 100 ether);
        uint256 startBalance = lp.balance;

        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pending",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(owner);
        pauseRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Soft,
            "soft pause"
        );

        vm.prank(lp);
        discovery.withdrawRegisterRequest();

        assertEq(
            uint8(discovery.getRegistrationState(lp)),
            uint8(IFlyoverDiscovery.RegistrationState.Withdrawn),
            "State should be Withdrawn after withdrawal"
        );
        assertEq(lp.balance, startBalance, "Collateral should be refunded");
    }

    function test_WithdrawRegisterRequest_RevertsDuringHardPause() public {
        address lp = makeAddr("lpWithdrawHardPause");
        vm.deal(lp, 100 ether);

        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pending",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(owner);
        pauseRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Hard,
            "hard pause"
        );

        vm.prank(lp);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        discovery.withdrawRegisterRequest();
    }

    function test_ApproveRegistration_RevertsForNonAdmin() public {
        address lp = makeAddr("lpNoAdmin");
        address stranger = makeAddr("stranger");
        vm.deal(lp, 100 ether);

        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pending",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.NotAuthorized.selector,
                stranger
            )
        );
        discovery.approveRegistration(lp);
    }

    function test_RejectRegistration_AllowsRefundDuringSoftPause() public {
        address lp = makeAddr("lpRejectSoftPause");
        vm.deal(lp, 100 ether);
        uint256 startBalance = lp.balance;

        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pending",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(owner);
        pauseRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Soft,
            "soft pause"
        );

        vm.prank(owner);
        discovery.rejectRegistration(lp);

        assertEq(
            uint8(discovery.getRegistrationState(lp)),
            uint8(IFlyoverDiscovery.RegistrationState.Rejected),
            "State should be Rejected after rejection"
        );
        assertEq(lp.balance, startBalance, "Collateral should be refunded");
    }

    function test_RejectRegistration_RevertsDuringHardPause() public {
        address lp = makeAddr("lpRejectHardPause");
        vm.deal(lp, 100 ether);

        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pending",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(owner);
        pauseRegistry.setPauseLevel(
            IPauseRegistry.PauseLevel.Hard,
            "hard pause"
        );

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        discovery.rejectRegistration(lp);
    }

    function test_GetRegistrationState_TracksLifecycle() public {
        address lp = makeAddr("lpState");
        vm.deal(lp, 100 ether);

        assertEq(
            uint8(discovery.getRegistrationState(lp)),
            uint8(IFlyoverDiscovery.RegistrationState.None),
            "Initial state should be None"
        );

        vm.prank(lp, lp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pending",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );
        assertEq(
            uint8(discovery.getRegistrationState(lp)),
            uint8(IFlyoverDiscovery.RegistrationState.Pending),
            "State should be Pending after register"
        );

        vm.prank(owner);
        discovery.approveRegistration(lp);
        assertEq(
            uint8(discovery.getRegistrationState(lp)),
            uint8(IFlyoverDiscovery.RegistrationState.Approved),
            "State should be Approved after approval"
        );

        address lp2 = makeAddr("lpState2");
        vm.deal(lp2, 100 ether);
        vm.prank(lp2, lp2);
        discovery.register{value: MIN_COLLATERAL}(
            "Pending2",
            "url2",
            true,
            Flyover.ProviderType.PegIn
        );
        vm.prank(lp2);
        discovery.withdrawRegisterRequest();
        assertEq(
            uint8(discovery.getRegistrationState(lp2)),
            uint8(IFlyoverDiscovery.RegistrationState.Withdrawn),
            "State should be Withdrawn after withdraw"
        );
    }
}
