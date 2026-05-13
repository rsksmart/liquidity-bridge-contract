// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {ICollateralManagement} from "../../src/interfaces/ICollateralManagement.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title Base contract for FlyoverDiscovery tests
/// @notice Provides shared deployment and setup logic
abstract contract DiscoveryTestBase is Test {
    PauseRegistry public pauseRegistry;
    FlyoverDiscovery public discovery;
    CollateralManagementContract public collateralManagement;

    address public owner;
    address public pegInLp;
    address public pegOutLp;
    address public fullLp;

    // Test constants
    uint48 constant TEST_DEFAULT_ADMIN_DELAY = 30;
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;
    uint256 constant TEST_RESIGN_DELAY_BLOCKS = 500;
    uint256 constant TEST_REWARD_PERCENTAGE = 1000;
    uint256 constant INITIAL_DELAY = 500;

    uint256 constant MIN_COLLATERAL = 0.6 ether;

    /// @dev Must match FlyoverDiscovery provider metadata limits
    uint256 constant MAX_PROVIDER_NAME_LENGTH = 256;
    uint256 constant MAX_PROVIDER_API_BASE_URL_LENGTH = 512;

    /// @notice Builds an ASCII string of exactly `len` bytes (for max-length validation tests)
    function makeStringOfLength(
        uint256 len
    ) internal pure returns (string memory) {
        bytes memory b = new bytes(len);
        for (uint256 i; i < len; ) {
            b[i] = bytes1(uint8(97 + (i % 26)));
            unchecked {
                ++i;
            }
        }
        return string(b);
    }

    /// @notice Deploy Discovery and CollateralManagement (equivalent to deployDiscoveryFixture)
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
        // Allow owner to add collateral directly for test setup
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            owner
        );
        // Grant COLLATERAL_ADDER role to FlyoverDiscovery contract
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            address(discovery)
        );
        vm.stopPrank();
    }

    /// @notice Setup providers with registrations (equivalent to deployDiscoveryWithProvidersFixture)
    function setupProviders() internal {
        pegInLp = makeAddr("pegInLp");
        pegOutLp = makeAddr("pegOutLp");
        fullLp = makeAddr("fullLp");

        // Fund providers
        vm.deal(pegInLp, 100 ether);
        vm.deal(pegOutLp, 100 ether);
        vm.deal(fullLp, 100 ether);

        // Register providers
        vm.prank(pegInLp, pegInLp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pegin Provider",
            "lp1.com",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(pegOutLp, pegOutLp);
        discovery.register{value: MIN_COLLATERAL}(
            "PegOut Provider",
            "lp2.com",
            true,
            Flyover.ProviderType.PegOut
        );

        vm.prank(fullLp, fullLp);
        discovery.register{value: MIN_COLLATERAL * 2}(
            "Full Provider",
            "lp3.com",
            true,
            Flyover.ProviderType.Both
        );
    }
}
