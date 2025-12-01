// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DiscoveryFuzzTestBase} from "./DiscoveryFuzzTestBase.sol";
import {IFlyoverDiscovery} from "../../../src/interfaces/IFlyoverDiscovery.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title FlyoverDiscovery Registration Fuzz Tests
/// @notice Fuzz tests for provider registration functionality
contract DiscoveryRegistrationFuzzTest is DiscoveryFuzzTestBase {
    function setUp() public {
        deployDiscovery();
        fuzzUser = makeAddr("fuzzUser");
        vm.deal(fuzzUser, 1000 ether);
    }

    // ============ Successful Registration Tests ============

    /// @notice Fuzz test: Registration with valid parameters succeeds
    function testFuzz_Register_SucceedsWithValidParameters(
        bytes32 nameSeed,
        bytes32 urlSeed,
        uint8 providerTypeRaw,
        uint256 extraCollateral
    ) public {
        string memory name = generateFuzzString(nameSeed, 1, 50);
        string memory url = generateFuzzString(urlSeed, 1, 100);
        Flyover.ProviderType providerType = getValidProviderType(providerTypeRaw);

        uint256 requiredCollateral = getRequiredCollateral(providerType);
        extraCollateral = bound(extraCollateral, 0, 10 ether);
        uint256 collateral = requiredCollateral + extraCollateral;

        address provider = createFundedEOA(string(abi.encodePacked("provider_", nameSeed)));

        vm.prank(provider);
        vm.expectEmit(true, true, true, true);
        emit IFlyoverDiscovery.Register(1, provider, collateral);
        uint256 providerId = discovery.register{value: collateral}(
            name,
            url,
            true,
            providerType
        );

        assertEq(providerId, 1, "Provider ID should be 1");
        assertEq(discovery.getProvidersId(), 1, "Last provider ID should be 1");

        Flyover.LiquidityProvider memory lp = discovery.getProvider(provider);
        assertEq(lp.id, 1, "Provider ID should match");
        assertEq(lp.providerAddress, provider, "Address should match");
        assertEq(lp.name, name, "Name should match");
        assertEq(lp.apiBaseUrl, url, "URL should match");
        assertTrue(lp.status, "Status should be true");
        assertEq(uint256(lp.providerType), uint256(providerType), "Type should match");
    }

    /// @notice Fuzz test: Registration increments provider ID correctly
    function testFuzz_Register_IncrementsProviderIdCorrectly(uint8 numProviders) public {
        numProviders = uint8(bound(numProviders, 1, 20));

        for (uint8 i = 0; i < numProviders; i++) {
            address provider = createFundedEOA(string(abi.encodePacked("lp_", i)));

            vm.prank(provider);
            uint256 providerId = discovery.register{value: MIN_COLLATERAL}(
                string(abi.encodePacked("Provider_", i)),
                string(abi.encodePacked("url_", i)),
                true,
                Flyover.ProviderType.PegIn
            );

            assertEq(providerId, i + 1, "Provider ID should increment");
        }

        assertEq(discovery.getProvidersId(), numProviders, "Last provider ID should match count");
    }

    /// @notice Fuzz test: Registration with status=false still works
    function testFuzz_Register_SucceedsWithStatusFalse(bytes32 nameSeed, bytes32 urlSeed) public {
        string memory name = generateFuzzString(nameSeed, 1, 50);
        string memory url = generateFuzzString(urlSeed, 1, 100);
        address provider = createFundedEOA("statusFalseProvider");

        vm.prank(provider);
        discovery.register{value: MIN_COLLATERAL}(
            name,
            url,
            false, // Status is false
            Flyover.ProviderType.PegIn
        );

        Flyover.LiquidityProvider memory lp = discovery.getProvider(provider);
        assertFalse(lp.status, "Status should be false");

        // Provider should NOT be in getProviders list (status=false)
        Flyover.LiquidityProvider[] memory providers = discovery.getProviders();
        assertEq(providers.length, 0, "Provider with status=false should not be listed");
    }

    // ============ Collateral Validation Tests ============

    /// @notice Fuzz test: Insufficient collateral for PegIn reverts
    function testFuzz_Register_RevertsOnInsufficientCollateralPegIn(uint256 collateral) public {
        collateral = bound(collateral, 0, MIN_COLLATERAL - 1);

        vm.prank(fuzzUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.InsufficientCollateral.selector,
                collateral
            )
        );
        discovery.register{value: collateral}(
            "Name",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );
    }

    /// @notice Fuzz test: Insufficient collateral for PegOut reverts
    function testFuzz_Register_RevertsOnInsufficientCollateralPegOut(uint256 collateral) public {
        collateral = bound(collateral, 0, MIN_COLLATERAL - 1);

        vm.prank(fuzzUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.InsufficientCollateral.selector,
                collateral
            )
        );
        discovery.register{value: collateral}(
            "Name",
            "url",
            true,
            Flyover.ProviderType.PegOut
        );
    }

    /// @notice Fuzz test: Insufficient collateral for Both reverts
    function testFuzz_Register_RevertsOnInsufficientCollateralBoth(uint256 collateral) public {
        collateral = bound(collateral, 0, MIN_COLLATERAL * 2 - 1);

        vm.prank(fuzzUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.InsufficientCollateral.selector,
                collateral
            )
        );
        discovery.register{value: collateral}(
            "Name",
            "url",
            true,
            Flyover.ProviderType.Both
        );
    }

    /// @notice Fuzz test: Exact minimum collateral succeeds
    function testFuzz_Register_SucceedsWithExactMinimumCollateral(uint8 providerTypeRaw) public {
        Flyover.ProviderType providerType = getValidProviderType(providerTypeRaw);
        uint256 requiredCollateral = getRequiredCollateral(providerType);

        vm.prank(fuzzUser);
        uint256 providerId = discovery.register{value: requiredCollateral}(
            "Name",
            "url",
            true,
            providerType
        );

        assertEq(providerId, 1, "Should register successfully");
    }

    // ============ Double Registration Tests ============

    /// @notice Fuzz test: Double registration by same address reverts
    function testFuzz_Register_RevertsOnDoubleRegistration(
        uint8 firstTypeRaw,
        uint8 secondTypeRaw
    ) public {
        Flyover.ProviderType firstType = getValidProviderType(firstTypeRaw);
        Flyover.ProviderType secondType = getValidProviderType(secondTypeRaw);
        uint256 firstCollateral = getRequiredCollateral(firstType);
        uint256 secondCollateral = getRequiredCollateral(secondType);

        // First registration succeeds
        vm.prank(fuzzUser);
        discovery.register{value: firstCollateral}(
            "First",
            "url1",
            true,
            firstType
        );

        // Second registration fails
        vm.prank(fuzzUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.AlreadyRegistered.selector,
                fuzzUser
            )
        );
        discovery.register{value: secondCollateral}(
            "Second",
            "url2",
            true,
            secondType
        );
    }

    // ============ Collateral Distribution Tests ============

    /// @notice Fuzz test: PegIn registration adds collateral only to PegIn
    function testFuzz_Register_PegInCollateralDistribution(uint256 extraCollateral) public {
        extraCollateral = bound(extraCollateral, 0, 5 ether);
        uint256 collateral = MIN_COLLATERAL + extraCollateral;

        vm.prank(fuzzUser);
        discovery.register{value: collateral}(
            "Name",
            "url",
            true,
            Flyover.ProviderType.PegIn
        );

        assertEq(
            collateralManagement.getPegInCollateral(fuzzUser),
            collateral,
            "PegIn collateral should match"
        );
        assertEq(
            collateralManagement.getPegOutCollateral(fuzzUser),
            0,
            "PegOut collateral should be 0"
        );
    }

    /// @notice Fuzz test: PegOut registration adds collateral only to PegOut
    function testFuzz_Register_PegOutCollateralDistribution(uint256 extraCollateral) public {
        extraCollateral = bound(extraCollateral, 0, 5 ether);
        uint256 collateral = MIN_COLLATERAL + extraCollateral;

        vm.prank(fuzzUser);
        discovery.register{value: collateral}(
            "Name",
            "url",
            true,
            Flyover.ProviderType.PegOut
        );

        assertEq(
            collateralManagement.getPegInCollateral(fuzzUser),
            0,
            "PegIn collateral should be 0"
        );
        assertEq(
            collateralManagement.getPegOutCollateral(fuzzUser),
            collateral,
            "PegOut collateral should match"
        );
    }

    /// @notice Fuzz test: Both registration splits collateral correctly
    function testFuzz_Register_BothCollateralDistribution(uint256 extraCollateral) public {
        extraCollateral = bound(extraCollateral, 0, 5 ether);
        uint256 collateral = MIN_COLLATERAL * 2 + extraCollateral;

        vm.prank(fuzzUser);
        discovery.register{value: collateral}(
            "Name",
            "url",
            true,
            Flyover.ProviderType.Both
        );

        uint256 halfAmount = collateral / 2;
        uint256 remainder = collateral % 2;

        assertEq(
            collateralManagement.getPegInCollateral(fuzzUser),
            halfAmount + remainder,
            "PegIn collateral should be half + remainder"
        );
        assertEq(
            collateralManagement.getPegOutCollateral(fuzzUser),
            halfAmount,
            "PegOut collateral should be half"
        );
    }

    // ============ Event Emission Tests ============

    /// @notice Fuzz test: Register emits correct event with all parameters
    function testFuzz_Register_EmitsCorrectEvent(
        bytes32 nameSeed,
        uint256 collateral,
        uint8 providerTypeRaw
    ) public {
        string memory name = generateFuzzString(nameSeed, 1, 50);
        Flyover.ProviderType providerType = getValidProviderType(providerTypeRaw);
        uint256 required = getRequiredCollateral(providerType);
        collateral = bound(collateral, required, required + 10 ether);

        address provider = createFundedEOA("eventProvider");

        vm.prank(provider);
        vm.expectEmit(true, true, true, true);
        emit IFlyoverDiscovery.Register(1, provider, collateral);
        discovery.register{value: collateral}(name, "url", true, providerType);
    }

    // ============ Contract Caller Tests ============

    /// @notice Fuzz test: Contract cannot register (NotEOA)
    function testFuzz_Register_RevertsForContract(uint8 providerTypeRaw) public {
        Flyover.ProviderType providerType = getValidProviderType(providerTypeRaw);
        uint256 collateral = getRequiredCollateral(providerType);

        // Use the discovery contract itself as a "contract caller" test
        // The contract address has code, so it should fail the EOA check
        vm.deal(address(discovery), 100 ether);

        vm.prank(address(discovery));
        vm.expectRevert(
            abi.encodeWithSelector(
                IFlyoverDiscovery.NotEOA.selector,
                address(discovery)
            )
        );
        discovery.register{value: collateral}(
            "Name",
            "url",
            true,
            providerType
        );
    }
}
