// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {PegOutContract} from "../../contracts/PegOutContract.sol";
import {CollateralManagementContract} from "../../contracts/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../contracts/FlyoverDiscovery.sol";
import {BridgeMock} from "../../contracts/test-contracts/BridgeMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Quotes} from "../../contracts/libraries/Quotes.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";

/// @title Base contract for PegOut tests
/// @notice Provides shared deployment and setup logic for PegOut tests
abstract contract PegOutTestBase is Test {
    PegOutContract public pegOutContract;
    CollateralManagementContract public collateralManagement;
    FlyoverDiscovery public discovery;
    BridgeMock public bridgeMock;

    address public owner;
    address public pegInLp;
    address public pegOutLp;
    address public fullLp;

    // Private keys for signing (needed for signature validation tests)
    uint256 public pegInLpKey;
    uint256 public pegOutLpKey;
    uint256 public fullLpKey;

    // Test constants
    uint48 constant TEST_DEFAULT_ADMIN_DELAY = 30;
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;
    uint256 constant TEST_RESIGN_DELAY_BLOCKS = 500;
    uint256 constant TEST_REWARD_PERCENTAGE = 1000;
    uint256 constant TEST_DUST_THRESHOLD = 0.0000001 ether; // From PEGOUT_CONSTANTS
    uint256 constant TEST_BTC_BLOCK_TIME = 3600;
    uint256 constant DISCOVERY_INITIAL_DELAY = 5000;
    uint256 constant MIN_COLLATERAL = 0.6 ether;

    address constant ZERO_ADDRESS = address(0);

    /// @notice Deploy PegOutContract with all dependencies
    function deployPegOutContract() internal {
        // Create owner
        owner = makeAddr("owner");
        vm.deal(owner, 100 ether);

        // Deploy CollateralManagement
        deployCollateralManagement();

        // Deploy Discovery
        deployDiscovery();

        // Deploy BridgeMock
        bridgeMock = new BridgeMock();

        // Deploy PegOutContract
        PegOutContract implementation = new PegOutContract();

        bytes memory initData = abi.encodeCall(
            PegOutContract.initialize,
            (
                owner,
                payable(address(bridgeMock)),
                TEST_DUST_THRESHOLD,
                address(collateralManagement),
                false, // mainnet
                TEST_BTC_BLOCK_TIME,
                0, // feePercentage
                payable(ZERO_ADDRESS) // feeCollector
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        pegOutContract = PegOutContract(payable(address(proxy)));

        // Grant COLLATERAL_SLASHER role to PegOutContract
        // Store the role hash BEFORE prank to avoid consuming it
        bytes32 slasherRole = collateralManagement.COLLATERAL_SLASHER();

        vm.prank(owner);
        collateralManagement.grantRole(slasherRole, address(pegOutContract));
    }

    function deployCollateralManagement() internal {
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

        // Verify owner has admin role (should be automatic with delay = 0)
        require(
            collateralManagement.hasRole(
                collateralManagement.DEFAULT_ADMIN_ROLE(),
                owner
            ),
            "Owner should have DEFAULT_ADMIN_ROLE"
        );
    }

    function deployDiscovery() internal {
        FlyoverDiscovery discoveryImplementation = new FlyoverDiscovery();

        bytes memory discoveryInitData = abi.encodeCall(
            FlyoverDiscovery.initialize,
            (
                owner,
                uint48(DISCOVERY_INITIAL_DELAY),
                address(collateralManagement)
            )
        );

        ERC1967Proxy discoveryProxy = new ERC1967Proxy(
            address(discoveryImplementation),
            discoveryInitData
        );
        discovery = FlyoverDiscovery(payable(address(discoveryProxy)));

        // Grant COLLATERAL_ADDER role to Discovery contract
        // Store the role hash BEFORE prank to avoid consuming it
        bytes32 adderRole = collateralManagement.COLLATERAL_ADDER();

        vm.prank(owner);
        collateralManagement.grantRole(adderRole, address(discovery));
    }

    /// @notice Setup providers with collateral
    function setupProviders() internal {
        // Create addresses with known private keys for signature testing
        (pegInLp, pegInLpKey) = makeAddrAndKey("pegInLp");
        (pegOutLp, pegOutLpKey) = makeAddrAndKey("pegOutLp");
        (fullLp, fullLpKey) = makeAddrAndKey("fullLp");

        // Fund providers
        vm.deal(pegInLp, 100 ether);
        vm.deal(pegOutLp, 100 ether);
        vm.deal(fullLp, 100 ether);

        // Register providers via Discovery
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
