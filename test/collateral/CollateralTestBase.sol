// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {ICollateralManagement} from "../../src/interfaces/ICollateralManagement.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title Base contract for CollateralManagement tests
/// @notice Provides shared deployment and setup logic
abstract contract CollateralTestBase is Test {
    PauseRegistry public pauseRegistry;
    CollateralManagementContract public collateralManagement;

    address public owner;
    address public adder;
    address public slasher;

    // Provider accounts
    address public pegInLp;
    address public pegOutLp;
    address public fullLp;

    // Test constants matching the TypeScript tests
    uint48 constant TEST_DEFAULT_ADMIN_DELAY = 30;
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;
    uint256 constant TEST_RESIGN_DELAY_BLOCKS = 500;
    uint256 constant TEST_REWARD_PERCENTAGE = 1000;

    uint256 constant ONE_RBTC = 1 ether;
    uint256 constant BASE_COLLATERAL = 10 ether;
    address constant ZERO_ADDRESS = address(0);

    /// @notice Deploy CollateralManagement with proxy (equivalent to deployCollateralManagement fixture)
    function deployCollateralManagement() internal {
        // Create test accounts
        owner = makeAddr("owner");

        // Fund owner
        vm.deal(owner, 100 ether);

        // Deploy PauseRegistry first
        PauseRegistry prImpl = new PauseRegistry();
        ERC1967Proxy prProxy = new ERC1967Proxy(
            address(prImpl),
            abi.encodeCall(prImpl.initialize, (0, owner))
        );
        pauseRegistry = PauseRegistry(payable(address(prProxy)));

        // Deploy implementation
        CollateralManagementContract implementation = new CollateralManagementContract();

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
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

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        collateralManagement = CollateralManagementContract(
            payable(address(proxy))
        );
    }

    /// @notice Setup roles (equivalent to deployCollateralManagementWithRoles fixture)
    function setupRoles() internal {
        adder = makeAddr("adder");
        slasher = makeAddr("slasher");

        // Fund accounts (adder needs more for tests that add large amounts)
        vm.deal(adder, 1000 ether);
        vm.deal(slasher, 100 ether);

        // Grant roles
        vm.startPrank(owner);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            adder
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            slasher
        );
        vm.stopPrank();
    }

    /// @notice Setup providers with collateral (equivalent to deployCollateralManagementWithProviders fixture)
    function setupProviders() internal {
        pegInLp = makeAddr("pegInLp");
        pegOutLp = makeAddr("pegOutLp");
        fullLp = makeAddr("fullLp");

        // Fund provider accounts
        vm.deal(pegInLp, 100 ether);
        vm.deal(pegOutLp, 100 ether);
        vm.deal(fullLp, 100 ether);

        // Add collateral for providers
        vm.startPrank(adder);
        collateralManagement.addPegInCollateralTo{value: BASE_COLLATERAL}(
            pegInLp
        );
        collateralManagement.addPegOutCollateralTo{value: BASE_COLLATERAL}(
            pegOutLp
        );
        collateralManagement.addPegInCollateralTo{value: BASE_COLLATERAL}(
            fullLp
        );
        collateralManagement.addPegOutCollateralTo{value: BASE_COLLATERAL}(
            fullLp
        );
        vm.stopPrank();
    }

    /// @notice Helper to create an empty PegIn quote
    function getEmptyPegInQuote()
        internal
        view
        returns (Quotes.PegInQuote memory)
    {
        bytes memory emptyBytes = new bytes(0);
        bytes memory testAddress = new bytes(20);

        return
            Quotes.PegInQuote({
                chainId: block.chainid,
                callFee: 0,
                penaltyFee: 0,
                value: 0,
                gasFee: 0,
                fedBtcAddress: bytes20(testAddress),
                lbcAddress: ZERO_ADDRESS,
                liquidityProviderRskAddress: ZERO_ADDRESS,
                contractAddress: ZERO_ADDRESS,
                rskRefundAddress: payable(ZERO_ADDRESS),
                nonce: 0,
                gasLimit: 0,
                agreementTimestamp: 0,
                timeForDeposit: 0,
                callTime: 0,
                depositConfirmations: 0,
                callOnRegister: false,
                btcRefundAddress: testAddress,
                liquidityProviderBtcAddress: testAddress,
                data: emptyBytes
            });
    }

    /// @notice Helper to create an empty PegOut quote
    function getEmptyPegOutQuote()
        internal
        view
        returns (Quotes.PegOutQuote memory)
    {
        bytes memory testAddress = new bytes(20);

        return
            Quotes.PegOutQuote({
                chainId: block.chainid,
                callFee: 0,
                penaltyFee: 0,
                value: 0,
                gasFee: 0,
                lbcAddress: ZERO_ADDRESS,
                lpRskAddress: ZERO_ADDRESS,
                rskRefundAddress: ZERO_ADDRESS,
                nonce: 0,
                agreementTimestamp: 0,
                depositDateLimit: 0,
                transferTime: 0,
                expireDate: 0,
                expireBlock: 0,
                depositConfirmations: 0,
                transferConfirmations: 0,
                depositAddress: testAddress,
                btcRefundAddress: testAddress,
                lpBtcAddress: testAddress
            });
    }
}
