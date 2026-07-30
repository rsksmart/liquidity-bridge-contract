// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {PegInDerivation} from "../../src/libraries/PegInDerivation.sol";

/// @title PegInDerivation Library Tests
/// @notice Pins the derivation vectors as FIXED-BYTE fixtures, PER NETWORK, and encodes the two
/// known derivation pitfalls as negative tests.
/// @dev Every expected value below is a pinned constant computed once offline by an independent
/// implementation of the scheme (keccak256/sha256/ripemd160 outside Solidity), never by calling the
/// library under test. Nothing is recomputed from the library's own constants: if any constant,
/// opcode, or version byte changes, these tests fail. That is the point.
///
/// Merged stack: #514 segwit P2SH-P2WSH wrapping + #515 per-network zero-address placeholders.
contract PegInDerivationTest is Test {
    // ---- Fixture inputs ----

    address internal constant FIXTURE_RSK = 0x0000000000000000000000000000000000000aBc;
    address internal constant FIXTURE_PEGIN_CONTRACT = 0x00000000000000000000000000000000C0FFEE01;
    bytes internal constant FIXTURE_POWPEG_SCRIPT =
        hex"522102cd53fc53a07f211641a677d250f6de99caf620e8e77071e811a28b3bcddf0be1210362634ab5"
        hex"7dae9cb373a5d536e66a8c4f67468bbcfb063809bab643072d78a1242103c5946b3fbae03a654237da86"
        hex"3c9ed534e0878657175b132b8ca630f245df04db53ae";

    // ---- Pinned protocol constants ----

    bytes internal constant PINNED_DOMAIN = hex"464c594f5645525f504547494e5f5631";
    bytes internal constant PINNED_PLACEHOLDER_TESTNET = hex"6f0000000000000000000000000000000000000000";
    bytes internal constant PINNED_PLACEHOLDER_MAINNET = hex"000000000000000000000000000000000000000000";

    // ---- Pinned step outputs, TESTNET/REGTEST ----

    bytes32 internal constant PINNED_ARGS_HASH = 0x0ac85b6d14264cdf09e4b64c6250b2fb650d8d87f04164e8f0c69b1f29e1a89a;
    bytes32 internal constant PINNED_DERIVATION_VALUE_TESTNET =
        0x6ca7b4e64cad153fbd1ddfda69945f982f204c662da0a904367b9ca593b42a9b;
    bytes internal constant PINNED_REDEEM_SCRIPT_TESTNET =
        hex"206ca7b4e64cad153fbd1ddfda69945f982f204c662da0a904367b9ca593b42a9b75522102cd53fc"
        hex"53a07f211641a677d250f6de99caf620e8e77071e811a28b3bcddf0be1210362634ab57dae9cb373"
        hex"a5d536e66a8c4f67468bbcfb063809bab643072d78a1242103c5946b3fbae03a654237da863c9ed5"
        hex"34e0878657175b132b8ca630f245df04db53ae";
    bytes internal constant PINNED_WITNESS_PROGRAM_TESTNET =
        hex"002036318fba28e8cf6f45f61f2d89b2347b561cb10bcc0b5d82b91891a5441cd77e";
    bytes20 internal constant PINNED_SCRIPT_HASH_TESTNET =
        bytes20(hex"90a45e9bf80f1a2d9aac68ef224d929bb9b507d8");
    bytes internal constant PINNED_SCRIPT_PUBKEY_TESTNET =
        hex"a91490a45e9bf80f1a2d9aac68ef224d929bb9b507d887";
    bytes internal constant PINNED_TESTNET_PAYLOAD =
        hex"c490a45e9bf80f1a2d9aac68ef224d929bb9b507d8545026ec";

    // ---- Pinned step outputs, MAINNET ----

    bytes32 internal constant PINNED_DERIVATION_VALUE_MAINNET =
        0x5f711554b557c7fa5da3126a212b7ef7ed5db9425be5eb872230eb1b356d235b;
    bytes internal constant PINNED_REDEEM_SCRIPT_MAINNET =
        hex"205f711554b557c7fa5da3126a212b7ef7ed5db9425be5eb872230eb1b356d235b75522102cd53fc"
        hex"53a07f211641a677d250f6de99caf620e8e77071e811a28b3bcddf0be1210362634ab57dae9cb373"
        hex"a5d536e66a8c4f67468bbcfb063809bab643072d78a1242103c5946b3fbae03a654237da863c9ed5"
        hex"34e0878657175b132b8ca630f245df04db53ae";
    bytes internal constant PINNED_WITNESS_PROGRAM_MAINNET =
        hex"0020dd15341bb89d7c5f914278d382662f80dd9c1b7162d6005fa0a63abe0bf3e34a";
    bytes20 internal constant PINNED_SCRIPT_HASH_MAINNET =
        bytes20(hex"ed4761212ddb2ff1ac15a2d401a32baeaa4bbabf");
    bytes internal constant PINNED_SCRIPT_PUBKEY_MAINNET =
        hex"a914ed4761212ddb2ff1ac15a2d401a32baeaa4bbabf87";
    bytes internal constant PINNED_MAINNET_PAYLOAD =
        hex"05ed4761212ddb2ff1ac15a2d401a32baeaa4bbabfdb51b9c1";

    // ---- Pinned negative-form payloads ----

    bytes internal constant PINNED_DIRECT_TAG_PAYLOAD =
        hex"c465e2519fcfd8e8f17bb35347261271ad75caa29c754165a5";
    bytes internal constant PINNED_PLAIN_WRAP_PAYLOAD =
        hex"c40c63443c601c577510e7f80cdd7f663e075dc07e862c627a";

    function test_DomainConstantIsPinned() public pure {
        assertEq(PegInDerivation.DERIVATION_DOMAIN, PINNED_DOMAIN, "DERIVATION_DOMAIN changed");
    }

    function test_RefundPlaceholderIsPinned() public pure {
        _assertZeroPlaceholder(
            PegInDerivation.refundPlaceholderBtc(false),
            PINNED_PLACEHOLDER_TESTNET,
            bytes1(0x6f),
            "refund testnet"
        );
        _assertZeroPlaceholder(
            PegInDerivation.refundPlaceholderBtc(true),
            PINNED_PLACEHOLDER_MAINNET,
            bytes1(0x00),
            "refund mainnet"
        );
    }

    function test_LpPlaceholderIsPinned() public pure {
        _assertZeroPlaceholder(
            PegInDerivation.lpPlaceholderBtc(false),
            PINNED_PLACEHOLDER_TESTNET,
            bytes1(0x6f),
            "lp testnet"
        );
        _assertZeroPlaceholder(
            PegInDerivation.lpPlaceholderBtc(true),
            PINNED_PLACEHOLDER_MAINNET,
            bytes1(0x00),
            "lp mainnet"
        );
    }

    function test_PlaceholdersDifferOnlyInVersionByte() public pure {
        bytes memory testnet = PegInDerivation.refundPlaceholderBtc(false);
        bytes memory mainnet = PegInDerivation.refundPlaceholderBtc(true);
        assertTrue(testnet[0] != mainnet[0], "version byte must differ between networks");
        for (uint256 i = 1; i < 21; ++i) {
            assertEq(testnet[i], mainnet[i], "only the version byte may differ");
        }
        assertEq(
            keccak256(PegInDerivation.lpPlaceholderBtc(false)),
            keccak256(testnet),
            "lp/refund testnet placeholders must match"
        );
        assertEq(
            keccak256(PegInDerivation.lpPlaceholderBtc(true)),
            keccak256(mainnet),
            "lp/refund mainnet placeholders must match"
        );
    }

    function test_Step1_DerivationArgumentsHash() public pure {
        assertEq(
            PegInDerivation.derivationArgumentsHash(FIXTURE_RSK),
            PINNED_ARGS_HASH,
            "step 1 drifted"
        );
    }

    function test_Step2_DerivationValue_Testnet() public pure {
        assertEq(
            PegInDerivation.derivationValue(FIXTURE_RSK, FIXTURE_PEGIN_CONTRACT, false),
            PINNED_DERIVATION_VALUE_TESTNET,
            "step 2 testnet drifted"
        );
    }

    function test_Step2_DerivationValue_Mainnet() public pure {
        assertEq(
            PegInDerivation.derivationValue(FIXTURE_RSK, FIXTURE_PEGIN_CONTRACT, true),
            PINNED_DERIVATION_VALUE_MAINNET,
            "step 2 mainnet drifted"
        );
    }

    function test_Step2_NetworksDeriveDifferentValues() public pure {
        assertTrue(
            PINNED_DERIVATION_VALUE_TESTNET != PINNED_DERIVATION_VALUE_MAINNET,
            "pinned per-network values must differ"
        );
        assertTrue(
            PegInDerivation.derivationValue(FIXTURE_RSK, FIXTURE_PEGIN_CONTRACT, false) !=
                PegInDerivation.derivationValue(FIXTURE_RSK, FIXTURE_PEGIN_CONTRACT, true),
            "mainnet flag must change the derivation value"
        );
    }

    function test_Step3_FlyoverRedeemScript_Testnet() public pure {
        assertEq(
            PegInDerivation.flyoverRedeemScript(PINNED_DERIVATION_VALUE_TESTNET, FIXTURE_POWPEG_SCRIPT),
            PINNED_REDEEM_SCRIPT_TESTNET,
            "step 3 testnet drifted"
        );
    }

    function test_Step3_FlyoverRedeemScript_Mainnet() public pure {
        assertEq(
            PegInDerivation.flyoverRedeemScript(PINNED_DERIVATION_VALUE_MAINNET, FIXTURE_POWPEG_SCRIPT),
            PINNED_REDEEM_SCRIPT_MAINNET,
            "step 3 mainnet drifted"
        );
    }

    function test_Step4a_WitnessProgram_Testnet() public pure {
        assertEq(
            PegInDerivation.witnessProgram(PINNED_REDEEM_SCRIPT_TESTNET),
            PINNED_WITNESS_PROGRAM_TESTNET,
            "step 4a testnet drifted"
        );
    }

    function test_Step4a_WitnessProgram_Mainnet() public pure {
        assertEq(
            PegInDerivation.witnessProgram(PINNED_REDEEM_SCRIPT_MAINNET),
            PINNED_WITNESS_PROGRAM_MAINNET,
            "step 4a mainnet drifted"
        );
    }

    function test_Step4b_FlyoverScriptHash_Testnet() public pure {
        assertEq(
            PegInDerivation.flyoverScriptHash(PINNED_REDEEM_SCRIPT_TESTNET),
            PINNED_SCRIPT_HASH_TESTNET,
            "step 4b testnet drifted"
        );
    }

    function test_Step4b_FlyoverScriptHash_Mainnet() public pure {
        assertEq(
            PegInDerivation.flyoverScriptHash(PINNED_REDEEM_SCRIPT_MAINNET),
            PINNED_SCRIPT_HASH_MAINNET,
            "step 4b mainnet drifted"
        );
    }

    function test_Step5a_P2shScriptPubkey_Testnet() public pure {
        assertEq(
            PegInDerivation.p2shScriptPubkey(PINNED_SCRIPT_HASH_TESTNET),
            PINNED_SCRIPT_PUBKEY_TESTNET,
            "step 5a testnet drifted"
        );
    }

    function test_Step5a_P2shScriptPubkey_Mainnet() public pure {
        assertEq(
            PegInDerivation.p2shScriptPubkey(PINNED_SCRIPT_HASH_MAINNET),
            PINNED_SCRIPT_PUBKEY_MAINNET,
            "step 5a mainnet drifted"
        );
    }

    function test_Step5b_TestnetPayload() public pure {
        assertEq(
            PegInDerivation.depositAddressPayload(PINNED_SCRIPT_HASH_TESTNET, false),
            PINNED_TESTNET_PAYLOAD,
            "step 5b testnet drifted"
        );
    }

    function test_Step5b_MainnetPayload() public pure {
        assertEq(
            PegInDerivation.depositAddressPayload(PINNED_SCRIPT_HASH_MAINNET, true),
            PINNED_MAINNET_PAYLOAD,
            "step 5b mainnet drifted"
        );
    }

    function test_FullChainMatchesPinnedFixtures() public pure {
        assertEq(
            PegInDerivation.depositAddressPayload(_deriveScriptHash(false), false),
            PINNED_TESTNET_PAYLOAD,
            "full-chain testnet payload drifted"
        );
        assertEq(
            PegInDerivation.depositAddressPayload(_deriveScriptHash(true), true),
            PINNED_MAINNET_PAYLOAD,
            "full-chain mainnet payload drifted"
        );
    }

    function test_FullChainNetworksDeriveDifferentScriptHashes() public pure {
        assertTrue(
            _deriveScriptHash(false) != _deriveScriptHash(true),
            "networks must derive different script hashes"
        );
    }

    function test_DerivationIsDeterministic() public pure {
        assertEq(_deriveScriptHash(false), _deriveScriptHash(false), "same inputs must derive the same script hash");
    }

    function test_DifferentRskAddressesDeriveDifferentAddresses() public pure {
        bytes32 valueA = PegInDerivation.derivationValue(address(0x1111), FIXTURE_PEGIN_CONTRACT, false);
        bytes32 valueB = PegInDerivation.derivationValue(address(0x2222), FIXTURE_PEGIN_CONTRACT, false);
        assertTrue(valueA != valueB, "different rskAddr must derive different values");
    }

    function test_Negative_DirectTagKeyingDivergesFromFixture() public pure {
        bytes memory wrongRedeemScript = PegInDerivation.flyoverRedeemScript(
            PegInDerivation.derivationArgumentsHash(FIXTURE_RSK),
            FIXTURE_POWPEG_SCRIPT
        );
        bytes memory wrongPayload = PegInDerivation.depositAddressPayload(
            PegInDerivation.flyoverScriptHash(wrongRedeemScript),
            false
        );
        assertEq(wrongPayload, PINNED_DIRECT_TAG_PAYLOAD, "direct-tag payload drifted from its pin");
        assertTrue(
            keccak256(wrongPayload) != keccak256(PINNED_TESTNET_PAYLOAD),
            "direct-tag keying must NOT produce the correct address"
        );
    }

    function test_Negative_PlainWrappingDivergesFromFixture() public pure {
        bytes memory wrongPayload = PegInDerivation.depositAddressPayload(
            ripemd160(abi.encodePacked(sha256(PINNED_REDEEM_SCRIPT_TESTNET))),
            false
        );
        assertEq(wrongPayload, PINNED_PLAIN_WRAP_PAYLOAD, "plain-wrap payload drifted from its pin");
        assertTrue(
            keccak256(wrongPayload) != keccak256(PINNED_TESTNET_PAYLOAD),
            "plain wrapping must NOT produce the correct address"
        );
    }

    function _assertZeroPlaceholder(
        bytes memory placeholder,
        bytes memory pinned,
        bytes1 version,
        string memory label
    ) private pure {
        assertEq(placeholder.length, 21, string.concat(label, ": must be 21 bytes (version ++ HASH160)"));
        assertEq(placeholder[0], version, string.concat(label, ": wrong version byte"));
        for (uint256 i = 1; i < 21; ++i) {
            assertEq(placeholder[i], bytes1(0x00), string.concat(label, ": HASH160 must be all zeroes"));
        }
        assertEq(placeholder, pinned, string.concat(label, ": placeholder changed"));
    }

    function _deriveScriptHash(bool mainnet) private pure returns (bytes20) {
        bytes32 derivationValue = PegInDerivation.derivationValue(FIXTURE_RSK, FIXTURE_PEGIN_CONTRACT, mainnet);
        bytes memory redeemScript = PegInDerivation.flyoverRedeemScript(derivationValue, FIXTURE_POWPEG_SCRIPT);
        return PegInDerivation.flyoverScriptHash(redeemScript);
    }
}
