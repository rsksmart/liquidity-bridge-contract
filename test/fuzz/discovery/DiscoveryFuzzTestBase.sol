// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {FlyoverDiscovery} from "../../../src/FlyoverDiscovery.sol";
import {CollateralManagementContract} from "../../../src/CollateralManagement.sol";
import {PauseRegistry} from "../../../src/PauseRegistry.sol";
import {ICollateralManagement} from "../../../src/interfaces/ICollateralManagement.sol";
import {IFlyoverDiscovery} from "../../../src/interfaces/IFlyoverDiscovery.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title Base contract for FlyoverDiscovery fuzz tests
/// @notice Provides shared deployment logic and helpers for fuzz testing
abstract contract DiscoveryFuzzTestBase is Test {
    PauseRegistry public pauseRegistry;
    FlyoverDiscovery public discovery;
    CollateralManagementContract public collateralManagement;

    address public owner;
    address public pegInLp;
    address public pegOutLp;
    address public fullLp;
    address public fuzzUser;

    // Private keys for signing (if needed)
    uint256 public pegInLpKey;
    uint256 public pegOutLpKey;
    uint256 public fullLpKey;

    // ============ Named Constants ============

    // Admin configuration
    uint48 constant TEST_DEFAULT_ADMIN_DELAY = 30;
    uint256 constant TEST_RESIGN_DELAY_BLOCKS = 500;
    uint256 constant TEST_REWARD_PERCENTAGE = 1000;
    uint256 constant INITIAL_DELAY = 500;

    // Collateral constants
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;
    uint256 constant MIN_COLLATERAL = 0.6 ether;
    uint256 constant MAX_COLLATERAL = 100 ether;

    // String length bounds
    uint256 constant MIN_STRING_LENGTH = 1;
    uint256 constant MAX_NAME_LENGTH = 100;
    uint256 constant MAX_URL_LENGTH = 200;

    // Provider type bounds
    uint8 constant PROVIDER_TYPE_PEGIN = 0;
    uint8 constant PROVIDER_TYPE_PEGOUT = 1;
    uint8 constant PROVIDER_TYPE_BOTH = 2;

    /// @notice Deploy Discovery and CollateralManagement contracts
    function deployDiscovery() internal {
        // Create test account
        owner = makeAddr("owner");
        vm.deal(owner, 100 ether);

        // Deploy PauseRegistry
        PauseRegistry prImpl = new PauseRegistry();
        ERC1967Proxy prProxy = new ERC1967Proxy(
            address(prImpl),
            abi.encodeCall(prImpl.initialize, (0, owner))
        );
        pauseRegistry = PauseRegistry(payable(address(prProxy)));

        // Deploy CollateralManagement
        CollateralManagementContract cmImplementation = new CollateralManagementContract();
        bytes memory cmInitData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                TEST_DEFAULT_ADMIN_DELAY,
                TEST_MIN_COLLATERAL,
                TEST_RESIGN_DELAY_BLOCKS,
                TEST_REWARD_PERCENTAGE,
                pauseRegistry
            )
        );
        ERC1967Proxy cmProxy = new ERC1967Proxy(
            address(cmImplementation),
            cmInitData
        );
        collateralManagement = CollateralManagementContract(
            payable(address(cmProxy))
        );

        // Deploy FlyoverDiscovery
        FlyoverDiscovery discoveryImplementation = new FlyoverDiscovery();
        bytes memory discoveryInitData = abi.encodeCall(
            FlyoverDiscovery.initialize,
            (
                owner,
                uint48(INITIAL_DELAY),
                address(collateralManagement),
                pauseRegistry
            )
        );
        ERC1967Proxy discoveryProxy = new ERC1967Proxy(
            address(discoveryImplementation),
            discoveryInitData
        );
        discovery = FlyoverDiscovery(payable(address(discoveryProxy)));

        // Grant roles
        vm.startPrank(owner);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            owner
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            address(discovery)
        );
        vm.stopPrank();
    }

    /// @notice Setup pre-registered providers
    function setupProviders() internal {
        (pegInLp, pegInLpKey) = makeAddrAndKey("pegInLp");
        (pegOutLp, pegOutLpKey) = makeAddrAndKey("pegOutLp");
        (fullLp, fullLpKey) = makeAddrAndKey("fullLp");

        // Fund providers
        vm.deal(pegInLp, 100 ether);
        vm.deal(pegOutLp, 100 ether);
        vm.deal(fullLp, 100 ether);

        // Register providers
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

    // ============ Helper Functions ============

    /// @notice Generate a valid random string for fuzz testing
    /// @param seed Random seed for string generation
    /// @param minLength Minimum string length
    /// @param maxLength Maximum string length
    /// @return result A random valid string
    function generateFuzzString(
        bytes32 seed,
        uint256 minLength,
        uint256 maxLength
    ) internal pure returns (string memory) {
        uint256 length = (uint256(seed) % (maxLength - minLength + 1)) +
            minLength;
        bytes memory result = new bytes(length);

        for (uint256 i = 0; i < length; i++) {
            // Generate printable ASCII characters (32-126)
            uint8 charCode = uint8(
                (uint256(keccak256(abi.encode(seed, i))) % 95) + 32
            );
            result[i] = bytes1(charCode);
        }

        return string(result);
    }

    /// @notice Get a valid provider type from a uint8
    /// @param typeIndex The raw type index
    /// @return providerType A valid ProviderType
    function getValidProviderType(
        uint8 typeIndex
    ) internal pure returns (Flyover.ProviderType) {
        uint8 bounded = typeIndex % 3;
        if (bounded == 0) return Flyover.ProviderType.PegIn;
        if (bounded == 1) return Flyover.ProviderType.PegOut;
        return Flyover.ProviderType.Both;
    }

    /// @notice Calculate required collateral for a provider type
    /// @param providerType The provider type
    /// @return required The minimum required collateral
    function getRequiredCollateral(
        Flyover.ProviderType providerType
    ) internal pure returns (uint256) {
        if (providerType == Flyover.ProviderType.Both) {
            return MIN_COLLATERAL * 2;
        }
        return MIN_COLLATERAL;
    }

    /// @notice Create a new EOA address with funds
    /// @param name The name for the address
    /// @return addr The new address
    function createFundedEOA(
        string memory name
    ) internal returns (address addr) {
        addr = makeAddr(name);
        vm.deal(addr, 100 ether);
        return addr;
    }

    /// @notice Register a provider with given parameters
    /// @param provider The provider address
    /// @param name Provider name
    /// @param url Provider API URL
    /// @param status Initial status
    /// @param providerType The provider type
    /// @param collateral Amount of collateral to send
    /// @return providerId The assigned provider ID
    function registerProvider(
        address provider,
        string memory name,
        string memory url,
        bool status,
        Flyover.ProviderType providerType,
        uint256 collateral
    ) internal returns (uint256 providerId) {
        vm.prank(provider);
        return
            discovery.register{value: collateral}(
                name,
                url,
                status,
                providerType
            );
    }
}
