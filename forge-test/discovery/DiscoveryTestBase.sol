// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {FlyoverDiscovery} from "../../contracts/FlyoverDiscovery.sol";
import {CollateralManagementContract} from "../../contracts/CollateralManagement.sol";
import {ICollateralManagement} from "../../contracts/interfaces/ICollateralManagement.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";

/// @title Base contract for FlyoverDiscovery tests
/// @notice Provides shared deployment and setup logic (equivalent to Hardhat fixtures)
abstract contract DiscoveryTestBase is Test {
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

    /// @notice Deploy Discovery and CollateralManagement (equivalent to deployDiscoveryFixture)
    function deployDiscovery() internal {
        // Create test account
        owner = makeAddr("owner");
        vm.deal(owner, 100 ether);

        // Deploy CollateralManagement
        CollateralManagementContract cmImplementation = new CollateralManagementContract();
        bytes memory cmInitData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                TEST_DEFAULT_ADMIN_DELAY,
                TEST_MIN_COLLATERAL,
                TEST_RESIGN_DELAY_BLOCKS,
                TEST_REWARD_PERCENTAGE
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
            (owner, uint48(INITIAL_DELAY), address(collateralManagement))
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
}
