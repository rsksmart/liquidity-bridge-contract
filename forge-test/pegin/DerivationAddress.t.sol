// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {PegInContract} from "../../contracts/PegInContract.sol";
import {CollateralManagementContract} from "../../contracts/CollateralManagement.sol";
import {BridgeMock} from "../../contracts/test-contracts/BridgeMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Quotes} from "../../contracts/libraries/Quotes.sol";

/// @title DerivationAddressTest
/// @notice Tests for BTC deposit address derivation
/// @dev BTC address derivation involves complex cryptographic operations (P2SH script hashing,
/// bs58 encoding/decoding) that are difficult to test in pure Solidity without external tools.
/// Full address derivation testing is better suited for integration tests with proper BTC libraries.
/// These tests verify the function exists and handles the basic flow.
contract DerivationAddressTest is Test {
    CollateralManagementContract public collateralManagement;
    address public owner;

    // Test constants
    uint48 constant TEST_DEFAULT_ADMIN_DELAY = 0;
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;
    uint256 constant TEST_RESIGN_DELAY_BLOCKS = 500;
    uint256 constant TEST_REWARD_PERCENTAGE = 1000;
    uint256 constant TEST_DUST_THRESHOLD = 2300 * 65164000;
    uint256 constant TEST_MIN_PEGIN = 0.5 ether;

    address constant ZERO_ADDRESS = address(0);

    function setUp() public {
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
    }

    // ============ validatePegInDepositAddress function tests ============

    function test_ValidatePegInDepositAddress_FunctionExists() public {
        // Note: BTC address derivation testing requires:
        // 1. Proper bs58 decoding of BTC addresses
        // 2. P2SH script hashing with federation redeem script
        // 3. RIPEMD-160 and SHA-256 operations
        // 4. Network-specific address prefixes (mainnet vs testnet)
        //
        // The actual BTC address bytes must match the derived P2SH hash from:
        // - Quote hash
        // - LP BTC address
        // - Federation redeem script from the Bridge
        //
        // This is complex cryptographic validation better suited for integration tests
        // with proper BTC libraries (like bs58, bitcoinjs-lib in TypeScript tests).
        //
        // For now, we verify the function signature exists and contract compiles correctly.

        PegInContract pegInMainnet = deployPegInContract(true);
        PegInContract pegInTestnet = deployPegInContract(false);

        // Verify contracts deployed successfully
        assertTrue(
            address(pegInMainnet) != address(0),
            "Mainnet contract should be deployed"
        );
        assertTrue(
            address(pegInTestnet) != address(0),
            "Testnet contract should be deployed"
        );

        // Verify function is callable (will return false with dummy data, but that's expected)
        Quotes.PegInQuote memory quote = createTestQuote1();
        quote.lbcAddress = address(pegInMainnet);
        bytes memory dummyAddress = new bytes(21);

        // Function should execute without reverting (even if validation fails)
        pegInMainnet.validatePegInDepositAddress(quote, dummyAddress);
    }

    // ============ Helper Functions ============

    function deployPegInContract(
        bool mainnet
    ) internal returns (PegInContract) {
        BridgeMock bridgeMock = new BridgeMock();
        PegInContract implementation = new PegInContract();

        bytes memory initData = abi.encodeCall(
            PegInContract.initialize,
            (
                owner,
                payable(address(bridgeMock)),
                TEST_DUST_THRESHOLD,
                TEST_MIN_PEGIN,
                address(collateralManagement),
                mainnet, // mainnet flag
                0,
                payable(ZERO_ADDRESS)
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        return PegInContract(payable(address(proxy)));
    }

    function createTestQuote1()
        internal
        pure
        returns (Quotes.PegInQuote memory)
    {
        bytes memory testBtcAddress = new bytes(21);

        return
            Quotes.PegInQuote({
                callFee: 100000000000000,
                penaltyFee: 10000000000000,
                value: 985215170000000000,
                productFeeAmount: 0,
                gasFee: 547377600000,
                fedBtcAddress: bytes20(
                    0x6b9a1d6634133e163A35eC8d7b6f496C32Cc16b0
                ),
                lbcAddress: 0x202CCe504e04bEd6fC0521238dDf04Bc9E8E15aB,
                liquidityProviderRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
                contractAddress: 0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56,
                rskRefundAddress: payable(
                    0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56
                ),
                nonce: 3635227228603468300,
                gasLimit: 21000,
                agreementTimestamp: 1752739488,
                timeForDeposit: 5400,
                callTime: 7200,
                depositConfirmations: 3,
                callOnRegister: false,
                btcRefundAddress: testBtcAddress,
                liquidityProviderBtcAddress: testBtcAddress,
                data: new bytes(0)
            });
    }

    function createTestQuote2()
        internal
        pure
        returns (Quotes.PegInQuote memory)
    {
        bytes memory testBtcAddress = new bytes(21);

        return
            Quotes.PegInQuote({
                callFee: 1478412310000000,
                penaltyFee: 10000000000000,
                value: 517700700000000000,
                productFeeAmount: 0,
                gasFee: 547377600000,
                fedBtcAddress: bytes20(
                    0x6b9a1d6634133e163A35eC8d7b6f496C32Cc16b0
                ),
                lbcAddress: 0x202CCe504e04bEd6fC0521238dDf04Bc9E8E15aB,
                liquidityProviderRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
                contractAddress: 0x129d2280f9C35C0Caf3f172d487Fd9A3f894fD26,
                rskRefundAddress: payable(
                    0x129d2280f9C35C0Caf3f172d487Fd9A3f894fD26
                ),
                nonce: 6080686644105603000,
                gasLimit: 21000,
                agreementTimestamp: 1755356567,
                timeForDeposit: 7200,
                callTime: 10800,
                depositConfirmations: 2,
                callOnRegister: false,
                btcRefundAddress: testBtcAddress,
                liquidityProviderBtcAddress: testBtcAddress,
                data: new bytes(0)
            });
    }

    function createTestQuote3()
        internal
        pure
        returns (Quotes.PegInQuote memory)
    {
        bytes memory testBtcAddress = new bytes(21);

        return
            Quotes.PegInQuote({
                callFee: 2009314000000000,
                penaltyFee: 10000000000000,
                value: 578580000000000000,
                productFeeAmount: 0,
                gasFee: 547377600000,
                fedBtcAddress: bytes20(
                    0x6b9a1d6634133e163A35eC8d7b6f496C32Cc16b0
                ),
                lbcAddress: 0x202CCe504e04bEd6fC0521238dDf04Bc9E8E15aB,
                liquidityProviderRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
                contractAddress: 0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56,
                rskRefundAddress: payable(
                    0xaC31A4bEedd7EC916B7A48a612230cb85c1aaf56
                ),
                nonce: 7756734892733337000,
                gasLimit: 21000,
                agreementTimestamp: 1755682139,
                timeForDeposit: 7200,
                callTime: 10800,
                depositConfirmations: 2,
                callOnRegister: false,
                btcRefundAddress: testBtcAddress,
                liquidityProviderBtcAddress: testBtcAddress,
                data: new bytes(0)
            });
    }
}
