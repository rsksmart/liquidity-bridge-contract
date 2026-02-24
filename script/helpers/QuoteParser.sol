// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {BtcAddressParser} from "./BtcAddressParser.sol";

/**
 * @title QuoteParser
 * @notice Shared utility for parsing PegIn and PegOut quotes from JSON
 * @dev Provides consistent quote parsing across all task scripts
 *
 * ## JSON Field Naming Convention
 *
 * ### PegIn Quote Fields:
 * - fedBTCAddr: Federation Bitcoin address (string)
 * - lbcAddr: LBC contract address (address)
 * - lpRSKAddr: LP RSK address (address)
 * - btcRefundAddr: BTC refund address (string)
 * - rskRefundAddr: RSK refund address (address)
 * - lpBTCAddr: LP Bitcoin address (string)
 * - callFee, penaltyFee, value, gasFee: (uint256)
 * - contractAddr: Destination contract address (address)
 * - data: Call data (bytes)
 * - gasLimit: Gas limit (uint32)
 * - nonce: Quote nonce (int64 or string)
 * - agreementTimestamp: Agreement timestamp (uint32)
 * - timeForDeposit: Time for deposit (uint32)
 * - lpCallTime: LP call time (uint32)
 * - confirmations: Deposit confirmations (uint16)
 * - callOnRegister: Whether to call on register (bool)
 *
 * ### PegOut Quote Fields:
 * - lbcAddress: LBC contract address (address)
 * - lpRskAddress: LP RSK address (address)
 * - btcRefundAddress: BTC refund address (string)
 * - rskRefundAddress: RSK refund address (address)
 * - lpBtcAddr: LP Bitcoin address (string)
 * - depositAddr: Deposit address (string)
 * - callFee, penaltyFee, value, gasFee: (uint256)
 * - nonce: Quote nonce (int64 or string)
 * - agreementTimestamp: Agreement timestamp (uint32)
 * - depositDateLimit: Deposit date limit (uint32)
 * - transferTime: Transfer time (uint32)
 * - depositConfirmations: Deposit confirmations (uint16)
 * - transferConfirmations: Transfer confirmations (uint16)
 * - expireBlocks: Expiration block (uint32)
 * - expireDate: Expiration date (uint32)
 */
abstract contract QuoteParser is BtcAddressParser {
    /// @notice Parse a PegIn quote from JSON string
    /// @param json The JSON string containing the quote data
    /// @return quote The parsed PegInQuote struct
    function parsePegInQuote(
        string memory json
    ) internal returns (Quotes.PegInQuote memory quote) {
        Vm vm = _getVm();

        // Parse Bitcoin addresses using FFI
        string memory fedBTCAddr = vm.parseJsonString(json, ".fedBTCAddr");
        quote.fedBtcAddress = parseFedBtcAddress(fedBTCAddr);

        // Parse RSK/EVM addresses
        quote.lbcAddress = vm.parseJsonAddress(json, ".lbcAddr");
        quote.liquidityProviderRskAddress = vm.parseJsonAddress(
            json,
            ".lpRSKAddr"
        );

        string memory btcRefundAddr = vm.parseJsonString(
            json,
            ".btcRefundAddr"
        );
        quote.btcRefundAddress = parseBtcAddress(btcRefundAddr);

        quote.rskRefundAddress = payable(
            vm.parseJsonAddress(json, ".rskRefundAddr")
        );

        string memory lpBTCAddr = vm.parseJsonString(json, ".lpBTCAddr");
        quote.liquidityProviderBtcAddress = parseBtcAddress(lpBTCAddr);

        // Parse numeric fields
        quote.callFee = vm.parseJsonUint(json, ".callFee");
        quote.penaltyFee = vm.parseJsonUint(json, ".penaltyFee");
        quote.contractAddress = vm.parseJsonAddress(json, ".contractAddr");
        quote.data = vm.parseJsonBytes(json, ".data");
        quote.gasLimit = uint32(vm.parseJsonUint(json, ".gasLimit"));

        // Parse nonce - handle both string and number formats
        quote.nonce = _parseNonce(vm, json);

        quote.value = vm.parseJsonUint(json, ".value");
        quote.agreementTimestamp = uint32(
            vm.parseJsonUint(json, ".agreementTimestamp")
        );
        quote.timeForDeposit = uint32(
            vm.parseJsonUint(json, ".timeForDeposit")
        );
        quote.callTime = uint32(vm.parseJsonUint(json, ".lpCallTime"));
        quote.depositConfirmations = uint16(
            vm.parseJsonUint(json, ".confirmations")
        );
        quote.callOnRegister = vm.parseJsonBool(json, ".callOnRegister");
        quote.gasFee = vm.parseJsonUint(json, ".gasFee");
        quote.chainId = block.chainid;
    }

    /// @notice Parse a PegOut quote from JSON string
    /// @param json The JSON string containing the quote data
    /// @return quote The parsed PegOutQuote struct
    function parsePegOutQuote(
        string memory json
    ) internal returns (Quotes.PegOutQuote memory quote) {
        Vm vm = _getVm();

        // Parse addresses
        quote.lbcAddress = vm.parseJsonAddress(json, ".lbcAddress");
        quote.lpRskAddress = vm.parseJsonAddress(json, ".lpRskAddress");

        string memory btcRefundAddr = vm.parseJsonString(
            json,
            ".btcRefundAddress"
        );
        quote.btcRefundAddress = parseBtcAddress(btcRefundAddr);

        quote.rskRefundAddress = vm.parseJsonAddress(json, ".rskRefundAddress");

        string memory lpBtcAddr = vm.parseJsonString(json, ".lpBtcAddr");
        quote.lpBtcAddress = parseBtcAddress(lpBtcAddr);

        // Parse numeric fields
        quote.callFee = vm.parseJsonUint(json, ".callFee");
        quote.penaltyFee = vm.parseJsonUint(json, ".penaltyFee");

        // Parse nonce - handle both string and number formats
        quote.nonce = _parseNonce(vm, json);

        string memory depositAddr = vm.parseJsonString(json, ".depositAddr");
        quote.depositAddress = parseBtcAddress(depositAddr);

        quote.value = vm.parseJsonUint(json, ".value");
        quote.agreementTimestamp = uint32(
            vm.parseJsonUint(json, ".agreementTimestamp")
        );
        quote.depositDateLimit = uint32(
            vm.parseJsonUint(json, ".depositDateLimit")
        );
        quote.transferTime = uint32(vm.parseJsonUint(json, ".transferTime"));
        quote.depositConfirmations = uint16(
            vm.parseJsonUint(json, ".depositConfirmations")
        );
        quote.transferConfirmations = uint16(
            vm.parseJsonUint(json, ".transferConfirmations")
        );
        quote.gasFee = vm.parseJsonUint(json, ".gasFee");
        quote.expireBlock = uint32(vm.parseJsonUint(json, ".expireBlocks"));
        quote.expireDate = uint32(vm.parseJsonUint(json, ".expireDate"));
    }

    /// @notice Parse nonce from JSON - handles both int and string formats
    /// @param vm The Forge VM instance
    /// @param json The JSON string
    /// @return The parsed nonce value
    function _parseNonce(
        Vm vm,
        string memory json
    ) private pure returns (int64) {
        try vm.parseJsonInt(json, ".nonce") returns (int256 nonceInt) {
            return int64(nonceInt);
        } catch {
            string memory nonceStr = vm.parseJsonString(json, ".nonce");
            return int64(uint64(vm.parseUint(nonceStr)));
        }
    }
}
