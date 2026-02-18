// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "../../pegout/PegOutTestBase.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";

/// @title Base contract for PegOut fuzz tests
/// @notice Provides shared helper functions for PegOut fuzz tests to reduce duplication
/// @dev Extends PegOutTestBase with fuzz-specific utilities
abstract contract PegOutFuzzTestBase is PegOutTestBase {
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

    /// @notice Default transfer time in seconds (1 hour)
    uint32 internal constant DEFAULT_TRANSFER_TIME = 3600;

    /// @notice Default deposit confirmations
    uint16 internal constant DEFAULT_DEPOSIT_CONFIRMATIONS = 10;

    /// @notice Default transfer confirmations
    uint16 internal constant DEFAULT_TRANSFER_CONFIRMATIONS = 2;

    /// @notice Default deposit date limit offset from current time (2 hours)
    uint32 internal constant DEFAULT_DEPOSIT_DATE_LIMIT_OFFSET = 7200;

    /// @notice Default expire date offset from current time
    uint32 internal constant DEFAULT_EXPIRE_DATE_OFFSET = 20000;

    /// @notice Default expire block offset from current block
    uint32 internal constant DEFAULT_EXPIRE_BLOCK_OFFSET = 1000;

    // ============ Quote Creation Helpers ============

    /// @notice Creates a test PegOut quote with the specified value
    /// @param value The value amount for the quote
    /// @return quote The created PegOut quote
    function createFuzzTestQuote(
        uint256 value
    ) internal view returns (Quotes.PegOutQuote memory) {
        return createFuzzTestQuoteForUser(value, fuzzUser);
    }

    /// @notice Creates a test PegOut quote with specified value and user address
    /// @param value The value amount for the quote
    /// @param userAddress The RSK refund address for the user
    /// @return quote The created PegOut quote
    function createFuzzTestQuoteForUser(
        uint256 value,
        address userAddress
    ) internal view returns (Quotes.PegOutQuote memory) {
        bytes memory testBtcAddress = abi.encodePacked(
            hex"6f", // Testnet P2PKH version byte
            hex"89abcdefabbaabbaabbaabbaabbaabbaabbaabba" // 20 bytes hash160
        );
        uint32 currentTime = uint32(block.timestamp);

        return
            Quotes.PegOutQuote({
                callFee: DEFAULT_CALL_FEE,
                penaltyFee: DEFAULT_PENALTY_FEE,
                value: value,
                gasFee: DEFAULT_GAS_FEE,
                lbcAddress: address(pegOutContract),
                lpRskAddress: pegOutLp,
                rskRefundAddress: userAddress,
                nonce: int64(uint64(block.timestamp)),
                agreementTimestamp: currentTime,
                depositDateLimit: currentTime +
                    DEFAULT_DEPOSIT_DATE_LIMIT_OFFSET,
                transferTime: DEFAULT_TRANSFER_TIME,
                depositConfirmations: DEFAULT_DEPOSIT_CONFIRMATIONS,
                transferConfirmations: DEFAULT_TRANSFER_CONFIRMATIONS,
                expireBlock: uint32(block.number + DEFAULT_EXPIRE_BLOCK_OFFSET),
                expireDate: currentTime + DEFAULT_EXPIRE_DATE_OFFSET,
                depositAddress: testBtcAddress,
                btcRefundAddress: testBtcAddress,
                lpBtcAddress: testBtcAddress
            });
    }

    /// @notice Creates a test PegOut quote with custom BTC address type
    /// @param value The value amount for the quote
    /// @param addressType The BTC address type ("p2pkh", "p2sh", "p2wpkh", "p2wsh", "p2tr")
    /// @param hash160 The 20-byte hash160 for the address
    /// @return quote The created PegOut quote
    function createFuzzTestQuoteWithAddressType(
        uint256 value,
        string memory addressType,
        bytes20 hash160
    ) internal view returns (Quotes.PegOutQuote memory) {
        bytes memory btcAddress;

        if (keccak256(bytes(addressType)) == keccak256(bytes("p2pkh"))) {
            btcAddress = abi.encodePacked(hex"6f", hash160);
        } else if (keccak256(bytes(addressType)) == keccak256(bytes("p2sh"))) {
            btcAddress = abi.encodePacked(hex"c4", hash160);
        } else if (
            keccak256(bytes(addressType)) == keccak256(bytes("p2wpkh"))
        ) {
            btcAddress = abi.encodePacked(hex"00", hash160);
        } else if (keccak256(bytes(addressType)) == keccak256(bytes("p2wsh"))) {
            btcAddress = abi.encodePacked(
                hex"00",
                hash160,
                hex"0000000000000000000000"
            ); // 32 bytes for WSH
        } else {
            // p2tr
            btcAddress = abi.encodePacked(
                hex"01",
                hash160,
                hex"0000000000000000000000"
            ); // 32 bytes for Taproot
        }

        uint32 currentTime = uint32(block.timestamp);

        return
            Quotes.PegOutQuote({
                callFee: DEFAULT_CALL_FEE,
                penaltyFee: DEFAULT_PENALTY_FEE,
                value: value,
                gasFee: DEFAULT_GAS_FEE,
                lbcAddress: address(pegOutContract),
                lpRskAddress: pegOutLp,
                rskRefundAddress: fuzzUser,
                nonce: int64(uint64(block.timestamp)),
                agreementTimestamp: currentTime,
                depositDateLimit: currentTime +
                    DEFAULT_DEPOSIT_DATE_LIMIT_OFFSET,
                transferTime: DEFAULT_TRANSFER_TIME,
                depositConfirmations: DEFAULT_DEPOSIT_CONFIRMATIONS,
                transferConfirmations: DEFAULT_TRANSFER_CONFIRMATIONS,
                expireBlock: uint32(block.number + DEFAULT_EXPIRE_BLOCK_OFFSET),
                expireDate: currentTime + DEFAULT_EXPIRE_DATE_OFFSET,
                depositAddress: btcAddress,
                btcRefundAddress: btcAddress,
                lpBtcAddress: btcAddress
            });
    }

    // ============ Value Calculation Helpers ============

    /// @notice Calculates the total value needed to deposit for a quote
    /// @param quote The PegOut quote
    /// @return The total value (value + callFee + gasFee)
    function getTotalQuoteValue(
        Quotes.PegOutQuote memory quote
    ) internal pure returns (uint256) {
        return quote.value + quote.callFee + quote.gasFee;
    }

    // ============ Signature Helpers ============

    /// @notice Signs a quote hash with the appropriate LP private key
    /// @param signer The signer address (must be one of the registered LPs)
    /// @param quoteHash The hash of the quote to sign
    /// @return signature The EIP-191 signature
    function signFuzzQuote(
        address signer,
        bytes32 quoteHash
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

        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", quoteHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }

    // ============ BTC Address Helpers ============

    /// @notice Extracts the 20-byte hash160 from a BTC address (skips version byte)
    /// @param btcAddress The BTC address bytes (with version prefix)
    /// @return hash160 The 20-byte hash160 extracted from the address
    function extractHash160(
        bytes memory btcAddress
    ) internal pure returns (bytes memory) {
        bytes memory hash160 = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            hash160[i] = btcAddress[i + 1];
        }
        return hash160;
    }

    /// @notice Returns the BTC address type string from an index
    /// @param index The address type index (0-3)
    /// @return addressType The address type string
    function getAddressTypeFromIndex(
        uint8 index
    ) internal pure returns (string memory) {
        if (index == 0) return "p2pkh";
        if (index == 1) return "p2sh";
        if (index == 2) return "p2wpkh";
        return "p2tr";
    }

    // ============ Combined Operations ============

    /// @notice Creates a quote, deposits it, and returns the quote
    /// @param value The value for the quote
    /// @return quote The created and deposited quote
    function createAndDepositFuzzQuote(
        uint256 value
    ) internal returns (Quotes.PegOutQuote memory) {
        Quotes.PegOutQuote memory quote = createFuzzTestQuote(value);
        bytes32 quoteHash = pegOutContract.hashPegOutQuote(quote);
        bytes memory signature = signFuzzQuote(pegOutLp, quoteHash);

        vm.prank(fuzzUser);
        pegOutContract.depositPegOut{value: getTotalQuoteValue(quote)}(
            quote,
            signature
        );

        return quote;
    }

    /// @notice Sets up the bridge mock with appropriate header and confirmations
    /// @param quote The quote for which to setup the bridge
    function setupFuzzBridgeMock(Quotes.PegOutQuote memory quote) internal {
        bytes memory header = createBtcBlockHeader(
            uint32(block.timestamp + 100)
        );
        bridgeMock.setHeaderByHash(BLOCK_HEADER_HASH, header);
        bridgeMock.setConfirmations(
            int256(uint256(quote.transferConfirmations))
        );
    }
}
