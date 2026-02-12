// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";

/// @title CollateralManagement Integration Tests
/// @notice Tests cross-contract interactions between CollateralManagement and Discovery
contract CollateralManagementIntegrationTest is Test {
    FlyoverDiscovery public discovery;
    CollateralManagementContract public collateralManagement;

    address public owner;
    address[] public signers;

    uint256 constant MIN_COLLATERAL = 0.6 ether;
    uint256 constant RESIGN_DELAY_BLOCKS = 500;

    bytes constant DECODED_TEST_FED_ADDRESS =
        hex"c39bc4b53918d6058134363d6e57e11a22f9e8fb";
    bytes constant DECODED_P2PKH_ZERO_ADDRESS_TESTNET =
        hex"6f0000000000000000000000000000000000000000";
    address constant ZERO_ADDRESS = address(0);

    function setUp() public {
        owner = address(this);

        // Create signers
        for (uint i = 0; i < 10; i++) {
            address signer = makeAddr(string.concat("signer", vm.toString(i)));
            vm.deal(signer, 100 ether);
            signers.push(signer);
        }

        // Deploy CollateralManagement
        CollateralManagementContract cmImpl = new CollateralManagementContract();
        bytes memory cmInitData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (owner, 30, MIN_COLLATERAL, RESIGN_DELAY_BLOCKS, 1000)
        );
        ERC1967Proxy cmProxy = new ERC1967Proxy(address(cmImpl), cmInitData);
        collateralManagement = CollateralManagementContract(
            payable(address(cmProxy))
        );

        // Deploy FlyoverDiscovery
        FlyoverDiscovery discoveryImpl = new FlyoverDiscovery();
        bytes memory discoveryInitData = abi.encodeCall(
            FlyoverDiscovery.initialize,
            (owner, 5000, address(collateralManagement))
        );
        ERC1967Proxy discoveryProxy = new ERC1967Proxy(
            address(discoveryImpl),
            discoveryInitData
        );
        discovery = FlyoverDiscovery(payable(address(discoveryProxy)));

        // Wait for admin delay and grant roles
        vm.warp(block.timestamp + 31);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            address(discovery)
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            owner
        );
    }

    function getEmptyPegInQuote()
        internal
        view
        returns (Quotes.PegInQuote memory)
    {
        return
            Quotes.PegInQuote({
                chainId: block.chainid,
                callFee: 0,
                value: 0,
                gasFee: 0,
                agreementTimestamp: 0,
                timeForDeposit: 0,
                callTime: 0,
                depositConfirmations: 0,
                callOnRegister: false,
                fedBtcAddress: bytes20(DECODED_TEST_FED_ADDRESS),
                lbcAddress: ZERO_ADDRESS,
                liquidityProviderRskAddress: ZERO_ADDRESS,
                btcRefundAddress: DECODED_P2PKH_ZERO_ADDRESS_TESTNET,
                rskRefundAddress: payable(ZERO_ADDRESS),
                liquidityProviderBtcAddress: DECODED_P2PKH_ZERO_ADDRESS_TESTNET,
                penaltyFee: 0,
                contractAddress: ZERO_ADDRESS,
                nonce: 0,
                gasLimit: 0,
                data: hex""
            });
    }

    // ============ Cross-contract: Adding Collateral Affects Discovery ============

    function test_ShouldMakeProviderOperationalInDiscoveryAfterAddingSufficientCollateral()
        public
    {
        address lp = signers[signers.length - 1];

        // Register with extra collateral
        vm.prank(lp);
        discovery.register{value: MIN_COLLATERAL * 2}(
            "LP",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        // Slash to below minimum (but not all)
        Quotes.PegInQuote memory quote = getEmptyPegInQuote();
        quote.liquidityProviderRskAddress = lp;
        quote.penaltyFee = MIN_COLLATERAL + MIN_COLLATERAL / 2; // Slash to below minimum but not zero

        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote,
            bytes32(0)
        );

        // Verify not operational in Discovery
        assertFalse(
            discovery.isOperational(Flyover.ProviderType.PegIn, lp),
            "Should not be operational"
        );

        // Add collateral in CollateralManagement
        vm.prank(lp);
        collateralManagement.addPegInCollateral{value: MIN_COLLATERAL}();

        // Verify operational again in Discovery
        assertTrue(
            discovery.isOperational(Flyover.ProviderType.PegIn, lp),
            "Should be operational again"
        );

        // Final collateral is: initial (2x) - slashed (1.5x) + added (1x) = 1.5x MIN_COLLATERAL
        assertEq(
            collateralManagement.getPegInCollateral(lp),
            MIN_COLLATERAL / 2 + MIN_COLLATERAL,
            "Final collateral should match"
        );
    }

    // ============ Cross-contract: Slashing Affects Discovery ============

    function test_ShouldMakeProviderNonOperationalInDiscoveryAfterSlashingBelowMinimum()
        public
    {
        address lp = signers[signers.length - 1];

        // Register with 2x minimum collateral
        vm.prank(lp);
        discovery.register{value: MIN_COLLATERAL * 2}(
            "LP",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        // Verify operational
        assertTrue(discovery.isOperational(Flyover.ProviderType.PegIn, lp));

        // Slash in CollateralManagement to below minimum
        Quotes.PegInQuote memory quote = getEmptyPegInQuote();
        quote.liquidityProviderRskAddress = lp;
        quote.penaltyFee = MIN_COLLATERAL * 2;

        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote,
            bytes32(0)
        );

        // Verify not operational in Discovery
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp));

        // Provider should also disappear from Discovery listing
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 0, "Provider should disappear from listing");
    }

    function test_ShouldKeepProviderInDiscoveryListingIfStillAboveMinimumAfterSlashing()
        public
    {
        address lp = signers[signers.length - 1];

        // Register with 3x minimum collateral
        vm.prank(lp);
        discovery.register{value: MIN_COLLATERAL * 3}(
            "LP",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        // Slash but keep above minimum
        Quotes.PegInQuote memory quote = getEmptyPegInQuote();
        quote.liquidityProviderRskAddress = lp;
        quote.penaltyFee = MIN_COLLATERAL;

        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote,
            bytes32(0)
        );

        // Still operational in Discovery
        assertTrue(discovery.isOperational(Flyover.ProviderType.PegIn, lp));

        // Still in Discovery listing
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 1);
        assertEq(providers[0].providerAddress, lp);
    }

    // ============ Cross-contract: Resignation Affects Discovery ============

    function test_ShouldImmediatelyHideProviderFromDiscoveryListingUponResignation()
        public
    {
        address lp1 = signers[signers.length - 2];
        address lp2 = signers[signers.length - 1];

        // Register two providers
        vm.prank(lp1);
        discovery.register{value: MIN_COLLATERAL}(
            "LP1",
            "url1",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(lp2);
        discovery.register{value: MIN_COLLATERAL}(
            "LP2",
            "url2",
            true,
            Flyover.ProviderType.PegIn
        );

        // Both listed in Discovery
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 2);

        // Resign LP1 in CollateralManagement
        vm.prank(lp1);
        collateralManagement.resign();

        // LP1 should disappear from Discovery listing immediately
        providers = discovery.getProviders();
        assertEq(providers.length, 1);
        assertEq(providers[0].providerAddress, lp2);

        // But LP1 can still be queried in Discovery
        Flyover.LiquidityProvider memory lp1Provider = discovery.getProvider(
            lp1
        );
        assertEq(lp1Provider.id, 1);

        // LP1 is not operational in Discovery
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp1));
    }

    function test_ShouldKeepProviderHiddenInDiscoveryEvenAfterWithdrawal()
        public
    {
        address lp = signers[signers.length - 1];

        // Register provider
        vm.prank(lp);
        discovery.register{value: MIN_COLLATERAL}(
            "LP",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        // Verify listed
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 1);

        // Resign in CollateralManagement
        vm.prank(lp);
        collateralManagement.resign();

        // Hidden from Discovery listing
        providers = discovery.getProviders();
        assertEq(providers.length, 0);

        // Withdraw collateral
        vm.roll(block.number + RESIGN_DELAY_BLOCKS);
        vm.prank(lp);
        collateralManagement.withdrawCollateral();

        // Still hidden from Discovery listing
        providers = discovery.getProviders();
        assertEq(providers.length, 0);

        // Still not operational
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp));

        // But can still be queried
        Flyover.LiquidityProvider memory provider = discovery.getProvider(lp);
        assertEq(provider.id, 1);
    }

    function test_ShouldAllowProviderToAppearInDiscoveryAgainAfterReRegistration()
        public
    {
        address lp = signers[signers.length - 1];

        // Initial registration
        vm.prank(lp);
        discovery.register{value: MIN_COLLATERAL}(
            "LP First",
            "url1",
            true,
            Flyover.ProviderType.PegIn
        );

        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 1);
        assertEq(providers[0].id, 1);

        // Resign and withdraw
        vm.prank(lp);
        collateralManagement.resign();

        vm.roll(block.number + RESIGN_DELAY_BLOCKS);

        vm.prank(lp);
        collateralManagement.withdrawCollateral();

        // Hidden from listing
        providers = discovery.getProviders();
        assertEq(providers.length, 0);

        // Re-register
        vm.prank(lp);
        discovery.register{value: MIN_COLLATERAL}(
            "LP Second",
            "url2",
            true,
            Flyover.ProviderType.PegOut
        );

        // Appears in listing again with new ID
        providers = discovery.getProviders();
        assertEq(providers.length, 1);
        assertEq(providers[0].id, 2);
        assertEq(providers[0].name, "LP Second");
        assertEq(
            uint8(providers[0].providerType),
            uint8(Flyover.ProviderType.PegOut)
        );

        // Operational for new type
        assertTrue(discovery.isOperational(Flyover.ProviderType.PegOut, lp));
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp));
    }

    // ============ Cross-contract: Complex Collateral Scenarios ============

    function test_ShouldHandleMultipleProvidersWithVaryingCollateralLevelsAffectingDiscovery()
        public
    {
        address lp1 = signers[signers.length - 4];
        address lp2 = signers[signers.length - 3];
        address lp3 = signers[signers.length - 2];
        address lp4 = signers[signers.length - 1];

        // Register 4 providers with different collateral amounts
        vm.prank(lp1);
        discovery.register{value: MIN_COLLATERAL}(
            "LP1",
            "url1",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(lp2);
        discovery.register{value: MIN_COLLATERAL * 2}(
            "LP2",
            "url2",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(lp3);
        discovery.register{value: MIN_COLLATERAL * 5}(
            "LP3",
            "url3",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(lp4);
        discovery.register{value: MIN_COLLATERAL * 10}(
            "LP4",
            "url4",
            true,
            Flyover.ProviderType.PegIn
        );

        // All should be operational and listed
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 4);

        // Slash LP1 to go below minimum (slashing caps at available amount)
        Quotes.PegInQuote memory quote1 = getEmptyPegInQuote();
        quote1.liquidityProviderRskAddress = lp1;
        quote1.penaltyFee = MIN_COLLATERAL + 1; // Slash all collateral

        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote1,
            bytes32(0)
        );

        // LP1 should disappear from Discovery
        providers = discovery.getProviders();
        assertEq(providers.length, 3);

        bool lp1Found = false;
        for (uint i = 0; i < providers.length; i++) {
            if (providers[i].providerAddress == lp1) {
                lp1Found = true;
                break;
            }
        }
        assertFalse(lp1Found, "LP1 should not be in listing");

        // Slash LP2 significantly but still above minimum
        Quotes.PegInQuote memory quote2 = getEmptyPegInQuote();
        quote2.liquidityProviderRskAddress = lp2;
        quote2.penaltyFee = MIN_COLLATERAL;

        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote2,
            bytes32(0)
        );

        // LP2 should still be listed
        providers = discovery.getProviders();
        assertEq(providers.length, 3);

        bool lp2Found = false;
        for (uint i = 0; i < providers.length; i++) {
            if (providers[i].providerAddress == lp2) {
                lp2Found = true;
                break;
            }
        }
        assertTrue(lp2Found, "LP2 should still be in listing");

        // Resign LP3
        vm.prank(lp3);
        collateralManagement.resign();

        // LP3 should disappear
        providers = discovery.getProviders();
        assertEq(providers.length, 2);

        bool lp3Found = false;
        for (uint i = 0; i < providers.length; i++) {
            if (providers[i].providerAddress == lp3) {
                lp3Found = true;
                break;
            }
        }
        assertFalse(lp3Found, "LP3 should not be in listing");

        // Only LP2 and LP4 should be listed
        assertEq(providers[0].providerAddress, lp2);
        assertEq(providers[1].providerAddress, lp4);

        // Verify operational status
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp1));
        assertTrue(discovery.isOperational(Flyover.ProviderType.PegIn, lp2));
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp3));
        assertTrue(discovery.isOperational(Flyover.ProviderType.PegIn, lp4));
    }
}
