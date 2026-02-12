// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "../../pegin/PegInTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {IPegIn} from "../../../src/interfaces/IPegIn.sol";

/// @title Base contract for PegIn fuzz tests
/// @notice Provides shared helper functions for PegIn fuzz tests to reduce duplication
/// @dev Extends PegInTestBase with fuzz-specific utilities
abstract contract PegInFuzzTestBase is PegInTestBase {
    /// @notice Address used as the user in fuzz tests
    /// @dev Child contracts should set this in their setUp() function
    address public fuzzUser;

    // ============ Named Constants ============

    /// @notice Default call fee for test quotes (0.0001 ether)
    uint256 internal constant DEFAULT_CALL_FEE = 100000000000000;

    /// @notice Default penalty fee for test quotes (0.00001 ether)
    uint256 internal constant DEFAULT_PENALTY_FEE = 10000000000000;

    /// @notice Default gas fee for test quotes
    uint256 internal constant DEFAULT_GAS_FEE = 100;

    /// @notice Default gas limit for calls
    uint32 internal constant DEFAULT_GAS_LIMIT = 21000;

    /// @notice Default time for deposit in seconds (1 hour)
    uint32 internal constant DEFAULT_TIME_FOR_DEPOSIT = 3600;

    /// @notice Default call time in seconds (2 hours)
    uint32 internal constant DEFAULT_CALL_TIME = 7200;

    /// @notice Default deposit confirmations
    uint16 internal constant DEFAULT_DEPOSIT_CONFIRMATIONS = 10;

    // ============ Quote Creation Helpers ============

    /// @notice Creates a test PegIn quote with the specified value
    /// @param value The value amount for the quote
    /// @return quote The created PegIn quote
    function createFuzzTestQuote(
        uint256 value
    ) internal view returns (Quotes.PegInQuote memory) {
        return createFuzzTestQuoteForLP(value, fuzzUser, fuzzUser, pegInLp);
    }

    /// @notice Creates a test PegIn quote with specified value and destination
    /// @param value The value amount for the quote
    /// @param destination The contract/address to call
    /// @param refund The refund address
    /// @return quote The created PegIn quote
    function createFuzzTestQuoteWithDestination(
        uint256 value,
        address destination,
        address refund
    ) internal view returns (Quotes.PegInQuote memory) {
        return createFuzzTestQuoteForLP(value, destination, refund, pegInLp);
    }

    /// @notice Creates a test PegIn quote for a specific LP
    /// @param value The value amount for the quote
    /// @param destination The contract/address to call
    /// @param refund The refund address
    /// @param lp The liquidity provider address
    /// @return quote The created PegIn quote
    function createFuzzTestQuoteForLP(
        uint256 value,
        address destination,
        address refund,
        address lp
    ) internal view returns (Quotes.PegInQuote memory) {
        return
            createFuzzTestQuoteForLPWithData(
                value,
                destination,
                refund,
                lp,
                new bytes(0)
            );
    }

    /// @notice Creates a test PegIn quote for a specific LP with custom call data
    /// @param value The value amount for the quote
    /// @param destination The contract/address to call
    /// @param refund The refund address
    /// @param lp The liquidity provider address
    /// @param data The call data
    /// @return quote The created PegIn quote
    function createFuzzTestQuoteForLPWithData(
        uint256 value,
        address destination,
        address refund,
        address lp,
        bytes memory data
    ) internal view returns (Quotes.PegInQuote memory) {
        bytes memory testBtcAddress = new bytes(21);
        testBtcAddress[0] = 0x6f; // Testnet version byte

        return
            Quotes.PegInQuote({
                chainId: block.chainid,
                callFee: DEFAULT_CALL_FEE,
                penaltyFee: DEFAULT_PENALTY_FEE,
                value: value,
                gasFee: DEFAULT_GAS_FEE,
                fedBtcAddress: bytes20(testBtcAddress),
                lbcAddress: address(pegInContract),
                liquidityProviderRskAddress: lp,
                contractAddress: destination,
                rskRefundAddress: payable(refund),
                nonce: int64(uint64(block.timestamp)),
                gasLimit: DEFAULT_GAS_LIMIT,
                agreementTimestamp: uint32(block.timestamp),
                timeForDeposit: DEFAULT_TIME_FOR_DEPOSIT,
                callTime: DEFAULT_CALL_TIME,
                depositConfirmations: DEFAULT_DEPOSIT_CONFIRMATIONS,
                callOnRegister: false,
                btcRefundAddress: testBtcAddress,
                liquidityProviderBtcAddress: testBtcAddress,
                data: data
            });
    }

    // ============ Value Calculation Helpers ============

    /// @notice Calculates the total value needed for a PegIn quote
    /// @param quote The PegIn quote
    /// @return The total value (value + callFee + gasFee)
    function getTotalQuoteValue(
        Quotes.PegInQuote memory quote
    ) internal pure returns (uint256) {
        return quote.value + quote.callFee + quote.gasFee;
    }

    // ============ Signature Helpers ============

    /// @notice Signs a quote with the appropriate LP private key
    /// @param signer The signer address (must be one of the registered LPs)
    /// @param quote The quote to sign
    /// @return signature The EIP-712 signature over the typed-data hash of the quote
    function signFuzzQuote(
        address signer,
        Quotes.PegInQuote memory quote
    ) internal view returns (bytes memory) {
        uint256 privateKey;
        if (signer == fullLp) {
            privateKey = fullLpKey;
        } else if (signer == pegInLp) {
            privateKey = pegInLpKey;
        } else if (signer == pegOutLp) {
            privateKey = pegOutLpKey;
        } else {
            revert("Unknown signer");
        }

        bytes32 eip712Hash = pegInContract.hashPegInQuoteEIP712(quote);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, eip712Hash);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Signs a message hash with the appropriate LP private key
    /// @param signer The signer address (must be one of the registered LPs)
    /// @param messageHash The message hash to sign
    /// @return signature The signature of the message hash
    function signMessageHash(
        address signer,
        bytes32 messageHash
    ) internal view returns (bytes memory) {
        uint256 privateKey;
        if (signer == fullLp) {
            privateKey = fullLpKey;
        } else if (signer == pegInLp) {
            privateKey = pegInLpKey;
        } else if (signer == pegOutLp) {
            privateKey = pegOutLpKey;
        } else {
            revert("Unknown signer");
        }

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    // ============ Combined Operations ============

    /// @notice Deposits funds for an LP and returns their new balance
    /// @param lp The LP address
    /// @param amount The amount to deposit
    /// @return newBalance The LP's balance after deposit
    function depositForLP(
        address lp,
        uint256 amount
    ) internal returns (uint256 newBalance) {
        vm.prank(lp);
        pegInContract.deposit{value: amount}();
        return pegInContract.getBalance(lp);
    }

    // ============ BTC Block Header Helpers ============

    /// @notice Creates a BTC block header with a specific timestamp (little-endian encoded)
    /// @param timestamp The Unix timestamp for the block
    /// @return header The 80-byte BTC block header
    function createBtcBlockHeader(
        uint32 timestamp
    ) internal pure returns (bytes memory) {
        // BTC block header structure (80 bytes total):
        // - Version: 4 bytes (set to 0)
        // - Previous block hash: 32 bytes (set to 0)
        // - Merkle root: 32 bytes (set to 0)
        // - Timestamp: 4 bytes (little-endian) at offset 68
        // - Bits: 4 bytes (set to 0)
        // - Nonce: 4 bytes (set to 0)
        bytes memory header = new bytes(80);

        // Convert timestamp to little-endian and place at offset 68
        header[68] = bytes1(uint8(timestamp));
        header[69] = bytes1(uint8(timestamp >> 8));
        header[70] = bytes1(uint8(timestamp >> 16));
        header[71] = bytes1(uint8(timestamp >> 24));

        return header;
    }
}
