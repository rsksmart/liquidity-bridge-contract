// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInFuzzTestBase} from "./PegInFuzzTestBase.sol";
import {PegInContract} from "../../../src/PegInContract.sol";
import {BtcAddressDataset} from "../../helpers/BtcAddressDataset.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {IPegIn} from "../../../src/interfaces/IPegIn.sol";

/// @title PegIn hashPegInQuote BTC address fuzz tests
/// @notice Verifies hashPegInQuote rejects non-P2PKH/P2SH BTC addresses using test/datasets fixtures
contract PegInHashPegInQuoteFuzzTest is PegInFuzzTestBase, BtcAddressDataset {
    PegInContract internal pegInContractMainnet;

    bytes[] internal invalidTestnetAddresses;
    bytes[] internal validTestnetAddresses;
    bytes[] internal validMainnetAddresses;
    bytes[] internal invalidMainnetAddresses;

    function setUp() public {
        pegInContract = deployPegInContract(false);
        pegInContractMainnet = deployPegInContract(true);
        fuzzUser = makeAddr("user");

        invalidTestnetAddresses = loadInvalidTestnetQuoteAddresses();
        validTestnetAddresses = loadValidTestnetQuoteAddresses();
        validMainnetAddresses = loadValidMainnetQuoteAddresses();
        invalidMainnetAddresses = loadInvalidMainnetQuoteAddresses();
    }

    /// @notice Fuzz: non-P2PKH/P2SH address on btcRefundAddress reverts on testnet
    function testFuzz_HashPegInQuote_RevertsOnInvalidBtcRefundAddress_Testnet(
        uint8 addressIndex
    ) public {
        addressIndex = uint8(
            bound(addressIndex, 0, invalidTestnetAddresses.length - 1)
        );

        bytes memory invalidAddress = invalidTestnetAddresses[addressIndex];
        assertInvalidTestnetScriptType(invalidAddress, addressIndex);

        Quotes.PegInQuote memory quote = createFuzzTestQuote(TEST_MIN_PEGIN);
        quote.btcRefundAddress = invalidAddress;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.InvalidRefundAddress.selector,
                invalidAddress
            )
        );
        pegInContract.hashPegInQuote(quote);
    }

    /// @notice Fuzz: non-P2PKH/P2SH address on liquidityProviderBtcAddress reverts on testnet
    function testFuzz_HashPegInQuote_RevertsOnInvalidLpBtcAddress_Testnet(
        uint8 addressIndex
    ) public {
        addressIndex = uint8(
            bound(addressIndex, 0, invalidTestnetAddresses.length - 1)
        );

        bytes memory invalidAddress = invalidTestnetAddresses[addressIndex];
        assertInvalidTestnetScriptType(invalidAddress, addressIndex);

        Quotes.PegInQuote memory quote = createFuzzTestQuote(TEST_MIN_PEGIN);
        quote.liquidityProviderBtcAddress = invalidAddress;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.InvalidRefundAddress.selector,
                invalidAddress
            )
        );
        pegInContract.hashPegInQuote(quote);
    }

    /// @notice Fuzz: P2WSH/P2TR addresses revert on mainnet deployment; P2WPKH shares the P2PKH prefix
    function testFuzz_HashPegInQuote_RevertsOnInvalidBtcAddress_Mainnet(
        uint8 addressIndex,
        uint8 validAddressIndex,
        bool targetRefundAddress
    ) public {
        addressIndex = uint8(
            bound(addressIndex, 0, invalidMainnetAddresses.length - 1)
        );
        validAddressIndex = uint8(
            bound(validAddressIndex, 0, validMainnetAddresses.length - 1)
        );

        bytes memory invalidAddress = invalidMainnetAddresses[addressIndex];
        bytes memory validAddress = validMainnetAddresses[validAddressIndex];

        Quotes.PegInQuote memory quote = _createMainnetFuzzQuote();
        quote.btcRefundAddress = validAddress;
        quote.liquidityProviderBtcAddress = validAddress;

        if (targetRefundAddress) {
            quote.btcRefundAddress = invalidAddress;
        } else {
            quote.liquidityProviderBtcAddress = invalidAddress;
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegIn.InvalidRefundAddress.selector,
                invalidAddress
            )
        );
        pegInContractMainnet.hashPegInQuote(quote);
    }

    /// @notice Fuzz: valid P2PKH/P2SH dataset addresses hash successfully on testnet
    function testFuzz_HashPegInQuote_AcceptsValidP2pkhAndP2shAddresses_Testnet(
        uint8 addressIndex
    ) public view {
        addressIndex = uint8(
            bound(addressIndex, 0, validTestnetAddresses.length - 1)
        );

        Quotes.PegInQuote memory quote = createFuzzTestQuote(TEST_MIN_PEGIN);
        bytes memory validAddress = validTestnetAddresses[addressIndex];
        quote.btcRefundAddress = validAddress;
        quote.liquidityProviderBtcAddress = validAddress;

        bytes32 hash = pegInContract.hashPegInQuote(quote);
        assertTrue(hash != bytes32(0), "Valid address should produce a hash");
    }

    function _createMainnetFuzzQuote()
        internal
        view
        returns (Quotes.PegInQuote memory quote)
    {
        quote = createFuzzTestQuote(TEST_MIN_PEGIN);
        quote.lbcAddress = address(pegInContractMainnet);
    }
}
