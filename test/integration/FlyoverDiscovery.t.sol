// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";

/// @title FlyoverDiscovery Integration Tests
/// @notice Tests cross-contract interactions between FlyoverDiscovery and CollateralManagement
contract FlyoverDiscoveryIntegrationTest is Test {
    FlyoverDiscovery public discovery;
    CollateralManagementContract public collateralManagement;

    address public owner;
    address[] public signers;
    address public pegInLp;
    address public pegOutLp;
    address public fullLp;

    uint256 constant MIN_COLLATERAL = 0.6 ether;
    uint256 constant RESIGN_DELAY_BLOCKS = 500;

    bytes constant DECODED_TEST_FED_ADDRESS =
        hex"c39bc4b53918d6058134363d6e57e11a22f9e8fb";
    bytes constant DECODED_P2PKH_ZERO_ADDRESS_TESTNET =
        hex"6f0000000000000000000000000000000000000000";
    address constant ZERO_ADDRESS = address(0);

    function getEmptyPegInQuote()
        internal
        pure
        returns (Quotes.PegInQuote memory)
    {
        return
            Quotes.PegInQuote({
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

        // Wait for admin delay and grant COLLATERAL_ADDER role
        vm.warp(block.timestamp + 31);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            address(discovery)
        );
    }

    function setupProviders() internal {
        pegInLp = signers[signers.length - 3];
        pegOutLp = signers[signers.length - 2];
        fullLp = signers[signers.length - 1];

        vm.prank(pegInLp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pegin Provider",
            "lp1.com",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(pegOutLp);
        discovery.register{value: MIN_COLLATERAL}(
            "PegOut Provider",
            "lp2.com",
            true,
            Flyover.ProviderType.PegOut
        );

        vm.prank(fullLp);
        discovery.register{value: MIN_COLLATERAL * 2}(
            "Full Provider",
            "lp3.com",
            true,
            Flyover.ProviderType.Both
        );
    }

    // ============ Cross-contract: Collateral Allocation During Registration ============

    function test_ShouldCorrectlyAllocateCollateralForProviderTypePegIn()
        public
    {
        address lp = signers[signers.length - 1];

        uint256 collateralAmount = MIN_COLLATERAL;

        vm.prank(lp);
        discovery.register{value: collateralAmount}(
            "PegIn LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegIn
        );

        // Verify collateral allocation in CollateralManagement contract
        assertEq(collateralManagement.getPegInCollateral(lp), collateralAmount);
        assertEq(collateralManagement.getPegOutCollateral(lp), 0);
    }

    function test_ShouldCorrectlyAllocateCollateralForProviderTypePegOut()
        public
    {
        address lp = signers[signers.length - 2];

        uint256 collateralAmount = MIN_COLLATERAL;

        vm.prank(lp);
        discovery.register{value: collateralAmount}(
            "PegOut LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegOut
        );

        // Verify collateral allocation in CollateralManagement contract
        assertEq(collateralManagement.getPegInCollateral(lp), 0);
        assertEq(
            collateralManagement.getPegOutCollateral(lp),
            collateralAmount
        );
    }

    function test_ShouldCorrectlyAllocateCollateralForProviderTypeBothWithEvenAmount()
        public
    {
        address lp = signers[signers.length - 3];

        uint256 evenAmount = MIN_COLLATERAL * 2;

        vm.prank(lp);
        discovery.register{value: evenAmount}(
            "Both LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.Both
        );

        // Verify exact 50/50 split in CollateralManagement
        uint256 expectedHalf = evenAmount / 2;
        assertEq(collateralManagement.getPegInCollateral(lp), expectedHalf);
        assertEq(collateralManagement.getPegOutCollateral(lp), expectedHalf);
    }

    function test_ShouldCorrectlyAllocateCollateralForProviderTypeBothWithOddAmount()
        public
    {
        address lp = signers[signers.length - 4];

        uint256 oddAmount = MIN_COLLATERAL * 2 + 1;

        vm.prank(lp);
        discovery.register{value: oddAmount}(
            "Both LP Odd",
            "http://localhost/api",
            true,
            Flyover.ProviderType.Both
        );

        // Verify PegIn gets the remainder in CollateralManagement
        uint256 halfAmount = oddAmount / 2;
        uint256 remainder = oddAmount % 2;
        uint256 expectedPegIn = halfAmount + remainder;
        uint256 expectedPegOut = halfAmount;

        assertEq(collateralManagement.getPegInCollateral(lp), expectedPegIn);
        assertEq(collateralManagement.getPegOutCollateral(lp), expectedPegOut);

        // Verify total allocation equals the original amount
        uint256 totalAllocated = collateralManagement.getPegInCollateral(lp) +
            collateralManagement.getPegOutCollateral(lp);
        assertEq(totalAllocated, oddAmount);
    }

    function test_ShouldVerifyCollateralIsActuallyTransferredToCollateralManagementContract()
        public
    {
        address lp = signers[signers.length - 5];

        // Get initial balance of CollateralManagement contract
        uint256 initialBalance = address(collateralManagement).balance;

        uint256 collateralAmount = MIN_COLLATERAL;

        vm.prank(lp);
        discovery.register{value: collateralAmount}(
            "Test LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegIn
        );

        // Verify the CollateralManagement contract received the funds
        uint256 finalBalance = address(collateralManagement).balance;
        assertEq(finalBalance - initialBalance, collateralAmount);
    }

    function test_ShouldEmitCorrectEventsInBothContractsDuringRegistration()
        public
    {
        address lp = signers[signers.length - 6];

        uint256 collateralAmount = MIN_COLLATERAL;

        vm.recordLogs();
        vm.prank(lp);
        discovery.register{value: collateralAmount}(
            "Event LP",
            "http://localhost/api",
            true,
            Flyover.ProviderType.PegIn
        );

        // Verify events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool foundRegisterEvent = false;
        bool foundPegInCollateralAddedEvent = false;

        for (uint i = 0; i < logs.length; i++) {
            // Register(uint256 indexed id, address indexed from, uint256 indexed amount)
            if (
                logs[i].topics[0] ==
                keccak256("Register(uint256,address,uint256)")
            ) {
                foundRegisterEvent = true;
            }
            // PegInCollateralAdded(address indexed provider, uint256 indexed amount)
            if (
                logs[i].topics[0] ==
                keccak256("PegInCollateralAdded(address,uint256)")
            ) {
                foundPegInCollateralAddedEvent = true;
            }
        }

        assertTrue(foundRegisterEvent, "Should emit Register event");
        assertTrue(
            foundPegInCollateralAddedEvent,
            "Should emit PegInCollateralAdded event"
        );
    }

    // ============ Cross-contract: isOperational Checks ============

    function test_ShouldReturnTrueOnlyForProvidersWithSufficientCollateralForTheirType()
        public
    {
        setupProviders();

        // Test PegIn operations (Discovery queries CollateralManagement)
        assertTrue(
            discovery.isOperational(Flyover.ProviderType.PegIn, pegInLp)
        );
        assertTrue(discovery.isOperational(Flyover.ProviderType.PegIn, fullLp));
        assertFalse(
            discovery.isOperational(Flyover.ProviderType.PegIn, pegOutLp)
        );

        // Test PegOut operations
        assertFalse(
            discovery.isOperational(Flyover.ProviderType.PegOut, pegInLp)
        );
        assertTrue(
            discovery.isOperational(Flyover.ProviderType.PegOut, fullLp)
        );
        assertTrue(
            discovery.isOperational(Flyover.ProviderType.PegOut, pegOutLp)
        );

        // Test Both operations (requires sufficient collateral for both PegIn AND PegOut)
        assertFalse(
            discovery.isOperational(Flyover.ProviderType.Both, pegInLp)
        ); // Only has PegIn collateral
        assertFalse(
            discovery.isOperational(Flyover.ProviderType.Both, pegOutLp)
        ); // Only has PegOut collateral
        assertTrue(discovery.isOperational(Flyover.ProviderType.Both, fullLp)); // Has both PegIn and PegOut collateral
    }

    function test_ShouldReflectCollateralSlashingInOperationalStatus() public {
        address lp = signers[signers.length - 1];

        // Register with enough collateral
        vm.prank(lp);
        discovery.register{value: MIN_COLLATERAL * 2}(
            "LP",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        // Initially operational
        assertTrue(discovery.isOperational(Flyover.ProviderType.PegIn, lp));

        // Grant COLLATERAL_SLASHER role
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            owner
        );

        // Slash some collateral (but still above minimum)
        Quotes.PegInQuote memory quote1 = getEmptyPegInQuote();
        quote1.liquidityProviderRskAddress = lp;
        quote1.penaltyFee = MIN_COLLATERAL / 2;

        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote1,
            bytes32(0)
        );

        // Still operational
        assertTrue(discovery.isOperational(Flyover.ProviderType.PegIn, lp));

        // Slash more to go below minimum
        Quotes.PegInQuote memory quote2 = getEmptyPegInQuote();
        quote2.liquidityProviderRskAddress = lp;
        quote2.penaltyFee = MIN_COLLATERAL;

        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote2,
            bytes32(0)
        );

        // No longer operational
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp));
    }

    function test_ShouldReflectCollateralAdditionsInOperationalStatus() public {
        address lp = signers[signers.length - 1];

        // Register with extra collateral
        vm.prank(lp);
        discovery.register{value: MIN_COLLATERAL * 2}(
            "LP",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        // Grant COLLATERAL_SLASHER role and slash below minimum (but not all)
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            owner
        );

        Quotes.PegInQuote memory quote = getEmptyPegInQuote();
        quote.liquidityProviderRskAddress = lp;
        quote.penaltyFee = MIN_COLLATERAL + MIN_COLLATERAL / 2;

        collateralManagement.slashPegInCollateral(
            ZERO_ADDRESS,
            quote,
            bytes32(0)
        );

        // Not operational (below minimum but still registered)
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp));

        // Add collateral back (provider is still registered so this works)
        vm.prank(lp);
        collateralManagement.addPegInCollateral{value: MIN_COLLATERAL}();

        // Operational again
        assertTrue(discovery.isOperational(Flyover.ProviderType.PegIn, lp));
    }

    // ============ Cross-contract: Resignation Flow ============

    function test_ShouldHideResignedProviderFromDiscoveryListing() public {
        address lp1 = signers[signers.length - 3];
        address lp2 = signers[signers.length - 2];
        address lp3 = signers[signers.length - 1];

        // Register multiple providers
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

        vm.prank(lp3);
        discovery.register{value: MIN_COLLATERAL}(
            "LP3",
            "url3",
            true,
            Flyover.ProviderType.PegIn
        );

        // Verify all listed
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 3);

        // Resign one provider in CollateralManagement
        vm.prank(lp2);
        collateralManagement.resign();

        // Verify disappeared from Discovery listing
        providers = discovery.getProviders();
        assertEq(providers.length, 2);
        assertEq(providers[0].id, 1);
        assertEq(providers[1].id, 3);

        // Verify getProvider still works
        Flyover.LiquidityProvider memory provider = discovery.getProvider(lp2);
        assertEq(provider.id, 2);

        // Verify isOperational returns false
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp2));
    }

    function test_ShouldCompleteFullResignationAndWithdrawalLifecycleAffectingDiscovery()
        public
    {
        address lp = signers[signers.length - 1];

        // Register provider (appears in Discovery)
        vm.prank(lp);
        discovery.register{value: MIN_COLLATERAL * 2}(
            "LP",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        assertEq(discovery.getProviders().length, 1);
        assertTrue(discovery.isOperational(Flyover.ProviderType.PegIn, lp));

        // Resign in CollateralManagement (disappears from Discovery list)
        vm.prank(lp);
        collateralManagement.resign();

        assertEq(discovery.getProviders().length, 0);
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp));

        // Wait resignation delay and withdraw
        vm.roll(block.number + RESIGN_DELAY_BLOCKS);

        vm.prank(lp);
        collateralManagement.withdrawCollateral();

        // Verify complete cleanup in CollateralManagement
        assertEq(collateralManagement.getPegInCollateral(lp), 0);
        assertEq(collateralManagement.getResignationBlock(lp), 0);

        // Discovery still knows the provider existed (but not operational)
        Flyover.LiquidityProvider memory provider = discovery.getProvider(lp);
        assertEq(provider.id, 1);
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp));
    }

    function test_ShouldSupportReRegistrationWithDifferentProviderTypeAfterFullResignationAndWithdrawal()
        public
    {
        address lp1 = signers[signers.length - 2];
        address lp2 = signers[signers.length - 1];

        // Register first provider as PegIn
        vm.prank(lp1);
        discovery.register{value: MIN_COLLATERAL}(
            "LP1 PegIn",
            "url1",
            true,
            Flyover.ProviderType.PegIn
        );

        Flyover.LiquidityProvider memory provider = discovery.getProvider(lp1);
        assertEq(
            uint8(provider.providerType),
            uint8(Flyover.ProviderType.PegIn)
        );
        assertEq(provider.id, 1);

        // Resign and withdraw first provider
        vm.prank(lp1);
        collateralManagement.resign();

        vm.roll(block.number + RESIGN_DELAY_BLOCKS);

        vm.prank(lp1);
        collateralManagement.withdrawCollateral();

        // Verify first provider is no longer operational
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp1));

        // Register second provider as PegOut (different address)
        vm.prank(lp2);
        discovery.register{value: MIN_COLLATERAL}(
            "LP2 PegOut",
            "url2",
            true,
            Flyover.ProviderType.PegOut
        );

        // Verify new provider type in Discovery
        provider = discovery.getProvider(lp2);
        assertEq(
            uint8(provider.providerType),
            uint8(Flyover.ProviderType.PegOut)
        );
        assertEq(provider.id, 2); // New ID assigned
        assertEq(provider.name, "LP2 PegOut");

        // Verify new collateral allocation in CollateralManagement
        assertEq(collateralManagement.getPegInCollateral(lp2), 0);
        assertEq(collateralManagement.getPegOutCollateral(lp2), MIN_COLLATERAL);

        // Verify operational for new provider
        assertTrue(discovery.isOperational(Flyover.ProviderType.PegOut, lp2));
        assertFalse(discovery.isOperational(Flyover.ProviderType.PegIn, lp2));
    }

    // ============ Complex Multi-Provider Scenario ============

    function test_ShouldListOnlyEnabledAndNonResignedProvidersInComplexScenario()
        public
    {
        // Create 8 providers with various states
        address lp1 = signers[signers.length - 8];
        address lp2 = signers[signers.length - 7];
        address lp3 = signers[signers.length - 6];
        address lp4 = signers[signers.length - 5];
        address lp5 = signers[signers.length - 4];
        address lp6 = signers[signers.length - 3];
        address lp7 = signers[signers.length - 2];
        address lp8 = signers[signers.length - 1];

        /**
         * Target provider statuses:
         * LP1 - active (enabled + not resigned)
         * LP2 - disabled but not resigned
         * LP3 - active (enabled + not resigned)
         * LP4 - resigned and disabled
         * LP5 - resigned but still enabled
         * LP6 - disabled but not resigned
         * LP7 - active (enabled + not resigned)
         * LP8 - resigned but enabled
         */

        // Register all 8 providers as enabled
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

        vm.prank(lp3);
        discovery.register{value: MIN_COLLATERAL}(
            "LP3",
            "url3",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(lp4);
        discovery.register{value: MIN_COLLATERAL}(
            "LP4",
            "url4",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(lp5);
        discovery.register{value: MIN_COLLATERAL}(
            "LP5",
            "url5",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(lp6);
        discovery.register{value: MIN_COLLATERAL}(
            "LP6",
            "url6",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(lp7);
        discovery.register{value: MIN_COLLATERAL}(
            "LP7",
            "url7",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(lp8);
        discovery.register{value: MIN_COLLATERAL}(
            "LP8",
            "url8",
            true,
            Flyover.ProviderType.PegIn
        );

        // All 8 should be listed initially
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 8, "All 8 providers should be listed initially");

        // LP2 - disable (not resigned)
        vm.prank(lp2);
        discovery.setProviderStatus(2, false);

        // LP3 - keep active (no changes)

        // LP4 - resign and disable
        vm.prank(lp4);
        discovery.setProviderStatus(4, false);
        vm.prank(lp4);
        collateralManagement.resign();

        // LP5 - resign but keep enabled
        vm.prank(lp5);
        collateralManagement.resign();

        // LP6 - disable (not resigned)
        vm.prank(lp6);
        discovery.setProviderStatus(6, false);

        // LP7 - keep active (no changes)

        // LP8 - resign but keep enabled
        vm.prank(lp8);
        collateralManagement.resign();

        // Get final provider list
        providers = discovery.getProviders();

        // Should only list: LP1, LP3, LP7 (enabled + not resigned)
        assertEq(providers.length, 3, "Should only list 3 active providers");
        assertEq(providers[0].id, 1, "First provider should be LP1");
        assertEq(providers[1].id, 3, "Second provider should be LP3");
        assertEq(providers[2].id, 7, "Third provider should be LP7");

        // Verify expected providers are in the list
        assertEq(providers[0].providerAddress, lp1, "LP1 address should match");
        assertEq(providers[0].name, "LP1", "LP1 name should match");
        assertTrue(providers[0].status, "LP1 should be enabled");

        assertEq(providers[1].providerAddress, lp3, "LP3 address should match");
        assertEq(providers[1].name, "LP3", "LP3 name should match");
        assertTrue(providers[1].status, "LP3 should be enabled");

        assertEq(providers[2].providerAddress, lp7, "LP7 address should match");
        assertEq(providers[2].name, "LP7", "LP7 name should match");
        assertTrue(providers[2].status, "LP7 should be enabled");

        // Verify LP2, LP4, LP5, LP6, LP8 are NOT in the list
        bool foundLp2 = false;
        bool foundLp4 = false;
        bool foundLp5 = false;
        bool foundLp6 = false;
        bool foundLp8 = false;

        for (uint i = 0; i < providers.length; i++) {
            if (providers[i].id == 2) foundLp2 = true;
            if (providers[i].id == 4) foundLp4 = true;
            if (providers[i].id == 5) foundLp5 = true;
            if (providers[i].id == 6) foundLp6 = true;
            if (providers[i].id == 8) foundLp8 = true;
        }

        assertFalse(foundLp2, "LP2 should not be in listing (disabled)");
        assertFalse(foundLp4, "LP4 should not be in listing (resigned and disabled)");
        assertFalse(foundLp5, "LP5 should not be in listing (resigned)");
        assertFalse(foundLp6, "LP6 should not be in listing (disabled)");
        assertFalse(foundLp8, "LP8 should not be in listing (resigned)");

        // But all providers still exist and can be queried
        Flyover.LiquidityProvider memory provider2 = discovery.getProvider(lp2);
        assertEq(provider2.id, 2, "LP2 should still exist");

        Flyover.LiquidityProvider memory provider4 = discovery.getProvider(lp4);
        assertEq(provider4.id, 4, "LP4 should still exist");

        Flyover.LiquidityProvider memory provider5 = discovery.getProvider(lp5);
        assertEq(provider5.id, 5, "LP5 should still exist");

        Flyover.LiquidityProvider memory provider6 = discovery.getProvider(lp6);
        assertEq(provider6.id, 6, "LP6 should still exist");

        Flyover.LiquidityProvider memory provider8 = discovery.getProvider(lp8);
        assertEq(provider8.id, 8, "LP8 should still exist");
    }
}
