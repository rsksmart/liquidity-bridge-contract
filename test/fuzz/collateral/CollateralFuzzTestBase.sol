// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {CollateralManagementContract} from "../../../src/CollateralManagement.sol";
import {ICollateralManagement} from "../../../src/interfaces/ICollateralManagement.sol";
import {PauseRegistry} from "../../../src/PauseRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title Base contract for CollateralManagement fuzz tests
/// @notice Provides shared deployment and setup logic for fuzz testing
abstract contract CollateralFuzzTestBase is Test {
    PauseRegistry public pauseRegistry;
    CollateralManagementContract public collateralManagement;

    address public owner;
    address public adder;
    address public slasher;

    // Provider accounts
    address public pegInLp;
    address public pegOutLp;
    address public fullLp;
    address public fuzzUser;

    // ============ Named Constants ============

    // Admin configuration
    uint48 constant TEST_DEFAULT_ADMIN_DELAY = 30;
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;
    uint256 constant TEST_RESIGN_DELAY_BLOCKS = 500;
    uint256 constant TEST_REWARD_PERCENTAGE = 1000; // 10%
    uint256 constant TOTAL_REWARD_PERCENTAGE = 10_000;

    // Collateral constants
    uint256 constant ONE_RBTC = 1 ether;
    uint256 constant BASE_COLLATERAL = 10 ether;
    uint256 constant MAX_COLLATERAL = 100 ether;

    // Quote constants
    uint256 constant DEFAULT_CALL_FEE = 100000000000000; // 1e14
    uint256 constant DEFAULT_PENALTY_FEE = 10000000000000; // 1e13
    uint256 constant DEFAULT_GAS_FEE = 100;
    uint256 constant DEFAULT_GAS_LIMIT = 21000;
    uint256 constant DEFAULT_QUOTE_VALUE = 1 ether;

    address constant ZERO_ADDRESS = address(0);

    /// @notice Deploy CollateralManagement with proxy
    function deployCollateralManagement() internal {
        owner = makeAddr("owner");
        vm.deal(owner, 100 ether);

        PauseRegistry prImpl = new PauseRegistry();
        ERC1967Proxy prProxy = new ERC1967Proxy(
            address(prImpl),
            abi.encodeCall(prImpl.initialize, (0, owner))
        );
        pauseRegistry = PauseRegistry(payable(address(prProxy)));

        CollateralManagementContract implementation = new CollateralManagementContract();

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

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        collateralManagement = CollateralManagementContract(
            payable(address(proxy))
        );
    }

    /// @notice Setup roles (adder and slasher)
    function setupRoles() internal {
        adder = makeAddr("adder");
        slasher = makeAddr("slasher");

        vm.deal(adder, 1000 ether);
        vm.deal(slasher, 100 ether);

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

    /// @notice Setup providers with initial collateral
    function setupProviders() internal {
        pegInLp = makeAddr("pegInLp");
        pegOutLp = makeAddr("pegOutLp");
        fullLp = makeAddr("fullLp");

        vm.deal(pegInLp, 100 ether);
        vm.deal(pegOutLp, 100 ether);
        vm.deal(fullLp, 100 ether);

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

    // ============ Helper Functions ============

    /// @notice Create a PegIn quote for testing
    function createPegInQuote(
        address liquidityProvider,
        uint256 penaltyFee
    ) internal pure returns (Quotes.PegInQuote memory quote) {
        bytes memory emptyBytes = new bytes(0);
        bytes memory testBtcAddress = new bytes(20);

        quote.callFee = DEFAULT_CALL_FEE;
        quote.penaltyFee = penaltyFee;
        quote.value = DEFAULT_QUOTE_VALUE;
        quote.liquidityProviderRskAddress = liquidityProvider;
        quote.gasLimit = uint32(DEFAULT_GAS_LIMIT);
        quote.btcRefundAddress = testBtcAddress;
        quote.liquidityProviderBtcAddress = testBtcAddress;
        quote.data = emptyBytes;
    }

    /// @notice Create a PegOut quote for testing
    function createPegOutQuote(
        address liquidityProvider,
        uint256 penaltyFee
    ) internal pure returns (Quotes.PegOutQuote memory quote) {
        bytes memory testBtcAddress = new bytes(20);

        quote.callFee = DEFAULT_CALL_FEE;
        quote.penaltyFee = penaltyFee;
        quote.value = DEFAULT_QUOTE_VALUE;
        quote.lpRskAddress = liquidityProvider;
        quote.depositAddress = testBtcAddress;
        quote.btcRefundAddress = testBtcAddress;
        quote.lpBtcAddress = testBtcAddress;
    }

    /// @notice Calculate reward for a given penalty
    function calculateReward(uint256 penalty) internal pure returns (uint256) {
        return (penalty * TEST_REWARD_PERCENTAGE) / TOTAL_REWARD_PERCENTAGE;
    }

    /// @notice Get a valid provider type from a uint8
    function getValidProviderType(
        uint8 typeIndex
    ) internal pure returns (Flyover.ProviderType) {
        uint8 bounded = typeIndex % 3;
        if (bounded == 0) return Flyover.ProviderType.PegIn;
        if (bounded == 1) return Flyover.ProviderType.PegOut;
        return Flyover.ProviderType.Both;
    }

    /// @notice Create a new funded EOA
    function createFundedEOA(
        string memory name
    ) internal returns (address addr) {
        addr = makeAddr(name);
        vm.deal(addr, 100 ether);
        return addr;
    }

    /// @notice Generate a unique quote hash
    function generateQuoteHash(uint256 seed) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, block.number, seed));
    }
}
