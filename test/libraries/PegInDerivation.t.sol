// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {PegInDerivation} from "../../src/libraries/PegInDerivation.sol";

/// @title PegInDerivation Library Tests
/// @notice Pins the derivation vectors as FIXED-BYTE fixtures and encodes the two known
/// derivation pitfalls as negative tests.
/// @dev Every expected value below is a pinned constant computed once offline. Nothing is
/// recomputed from the library's own constants: if any constant, opcode, or version byte changes,
/// these tests fail. That is the point.
contract PegInDerivationTest is Test {
    // ---- Fixture inputs ----

    /// @notice The RSK destination address of the pinned vector
    address internal constant FIXTURE_RSK =
        0x0000000000000000000000000000000000000aBc;

    /// @notice The PegInContract (lbcAddress) mixed into the pinned vector
    address internal constant FIXTURE_PEGIN_CONTRACT =
        0x00000000000000000000000000000000C0FFEE01;

    /// @notice The active powpeg redeem script of the pinned vector
    bytes internal constant FIXTURE_POWPEG_SCRIPT =
        hex"522102cd53fc53a07f211641a677d250f6de99caf620e8e77071e811a28b3bcddf0be1210362634ab5"
        hex"7dae9cb373a5d536e66a8c4f67468bbcfb063809bab643072d78a1242103c5946b3fbae03a654237da86"
        hex"3c9ed534e0878657175b132b8ca630f245df04db53ae";

    // ---- Pinned protocol constants ----

    /// @notice The exact bytes of DERIVATION_DOMAIN ("FLYOVER_PEGIN_V1")
    bytes internal constant PINNED_DOMAIN =
        hex"464c594f5645525f504547494e5f5631";

    /// @notice The exact 21-byte (version ++ HASH160) placeholder both BTC-address slots ship with
    bytes internal constant PINNED_PLACEHOLDER =
        hex"6f044f0ba3d3a2bd0724db5e6d59a0bb62f4ef0cc2";

    // ---- Pinned step outputs (computed once offline, frozen) ----

    /// @notice Step 1: keccak256(DERIVATION_DOMAIN ++ rskAddr)
    bytes32 internal constant PINNED_ARGS_HASH =
        0x0ac85b6d14264cdf09e4b64c6250b2fb650d8d87f04164e8f0c69b1f29e1a89a;

    /// @notice Step 2: keccak256(argsHash ++ placeholder ++ bytes20(pegInContract) ++ placeholder)
    bytes32 internal constant PINNED_DERIVATION_VALUE =
        0xae132ee60570d9332790a147f626edd2c053c2ea9fbece393e2caf823a8746b6;

    /// @notice Step 3: OP_PUSHBYTES_32 ++ derivationValue ++ OP_DROP ++ powpeg script
    bytes internal constant PINNED_REDEEM_SCRIPT =
        hex"20ae132ee60570d9332790a147f626edd2c053c2ea9fbece393e2caf823a8746b675522102cd53fc53"
        hex"a07f211641a677d250f6de99caf620e8e77071e811a28b3bcddf0be1210362634ab57dae9cb373a5d5"
        hex"36e66a8c4f67468bbcfb063809bab643072d78a1242103c5946b3fbae03a654237da863c9ed534e087"
        hex"8657175b132b8ca630f245df04db53ae";

    /// @notice Step 4a: OP_0 ++ OP_PUSHBYTES_32 ++ sha256(flyover redeem script)
    bytes internal constant PINNED_WITNESS_PROGRAM =
        hex"00202250d436563469d5b31fb4633242759c8924a26067ecab78001da7af03a5397d";

    /// @notice Step 4b: HASH160 of the witness program
    bytes20 internal constant PINNED_SCRIPT_HASH =
        bytes20(hex"23670b6bf4ab398f05d8536da400767b562425bc");

    /// @notice Step 5a: OP_HASH160 0x14 <scriptHash> OP_EQUAL
    bytes internal constant PINNED_SCRIPT_PUBKEY =
        hex"a91423670b6bf4ab398f05d8536da400767b562425bc87";

    /// @notice Step 5b testnet: 0xC4 ++ scriptHash ++ checksum
    bytes internal constant PINNED_TESTNET_PAYLOAD =
        hex"c423670b6bf4ab398f05d8536da400767b562425bc199d1a4a";

    /// @notice Step 5b mainnet: 0x05 ++ scriptHash ++ checksum
    bytes internal constant PINNED_MAINNET_PAYLOAD =
        hex"0523670b6bf4ab398f05d8536da400767b562425bc89840387";

    // ---- Pinned negative-form payloads (the two on-chain failure modes) ----

    /// @notice Pitfall #1 (-900): payload derived keying the redeem-script tag with the
    /// derivationArgumentsHash DIRECTLY, skipping step 2's address mixing
    bytes internal constant PINNED_DIRECT_TAG_PAYLOAD =
        hex"c465e2519fcfd8e8f17bb35347261271ad75caa29c754165a5";

    /// @notice Pitfall #2 (-304): payload derived wrapping the CORRECT redeem script as a plain
    /// P2SH (the pre-segwit federation form) instead of a P2SH-of-P2WSH
    bytes internal constant PINNED_PLAIN_WRAP_PAYLOAD =
        hex"c453239f29b16aa66c9a5e3ec7f2b1de034fe0dea79440b320";

    // ---- Constant pinning ----

    function test_DomainConstantIsPinned() public pure {
        assertEq(
            PegInDerivation.DERIVATION_DOMAIN,
            PINNED_DOMAIN,
            "DERIVATION_DOMAIN changed"
        );
    }

    function test_RefundPlaceholderIsPinned() public pure {
        bytes memory placeholder = PegInDerivation.refundPlaceholderBtc();
        assertEq(
            placeholder.length,
            21,
            "refund placeholder must be 21 bytes (version ++ HASH160)"
        );
        assertEq(
            placeholder,
            PINNED_PLACEHOLDER,
            "REFUND_PLACEHOLDER_BTC changed"
        );
    }

    function test_LpPlaceholderIsPinned() public pure {
        bytes memory placeholder = PegInDerivation.lpPlaceholderBtc();
        assertEq(
            placeholder.length,
            21,
            "lp placeholder must be 21 bytes (version ++ HASH160)"
        );
        assertEq(placeholder, PINNED_PLACEHOLDER, "LP_PLACEHOLDER_BTC changed");
    }

    // ---- Per-step fixtures (each step fed the PINNED previous output) ----

    function test_Step1_DerivationArgumentsHash() public pure {
        assertEq(
            PegInDerivation.derivationArgumentsHash(FIXTURE_RSK),
            PINNED_ARGS_HASH,
            "step 1 drifted"
        );
    }

    function test_Step2_DerivationValue() public pure {
        assertEq(
            PegInDerivation.derivationValue(
                FIXTURE_RSK,
                FIXTURE_PEGIN_CONTRACT
            ),
            PINNED_DERIVATION_VALUE,
            "step 2 drifted"
        );
    }

    function test_Step3_FlyoverRedeemScript() public pure {
        assertEq(
            PegInDerivation.flyoverRedeemScript(
                PINNED_DERIVATION_VALUE,
                FIXTURE_POWPEG_SCRIPT
            ),
            PINNED_REDEEM_SCRIPT,
            "step 3 drifted"
        );
    }

    function test_Step4a_WitnessProgram() public pure {
        assertEq(
            PegInDerivation.witnessProgram(PINNED_REDEEM_SCRIPT),
            PINNED_WITNESS_PROGRAM,
            "step 4a drifted"
        );
    }

    function test_Step4b_FlyoverScriptHash() public pure {
        assertEq(
            PegInDerivation.flyoverScriptHash(PINNED_REDEEM_SCRIPT),
            PINNED_SCRIPT_HASH,
            "step 4b drifted"
        );
    }

    function test_Step5a_P2shScriptPubkey() public pure {
        assertEq(
            PegInDerivation.p2shScriptPubkey(PINNED_SCRIPT_HASH),
            PINNED_SCRIPT_PUBKEY,
            "step 5a drifted"
        );
    }

    function test_Step5b_TestnetPayload() public pure {
        assertEq(
            PegInDerivation.depositAddressPayload(PINNED_SCRIPT_HASH, false),
            PINNED_TESTNET_PAYLOAD,
            "step 5b testnet drifted"
        );
    }

    function test_Step5b_MainnetPayload() public pure {
        assertEq(
            PegInDerivation.depositAddressPayload(PINNED_SCRIPT_HASH, true),
            PINNED_MAINNET_PAYLOAD,
            "step 5b mainnet drifted"
        );
    }

    // ---- Full chain, composed the way consumers compose it ----

    function test_FullChainMatchesPinnedFixture() public pure {
        bytes20 scriptHash = _deriveScriptHash();
        assertEq(
            PegInDerivation.depositAddressPayload(scriptHash, false),
            PINNED_TESTNET_PAYLOAD,
            "full-chain testnet payload drifted"
        );
        assertEq(
            PegInDerivation.depositAddressPayload(scriptHash, true),
            PINNED_MAINNET_PAYLOAD,
            "full-chain mainnet payload drifted"
        );
    }

    function test_DerivationIsDeterministic() public pure {
        bytes20 first = _deriveScriptHash();
        bytes20 second = _deriveScriptHash();
        assertEq(first, second, "same inputs must derive the same script hash");
    }

    function test_DifferentRskAddressesDeriveDifferentAddresses() public pure {
        bytes32 valueA = PegInDerivation.derivationValue(
            address(0x1111),
            FIXTURE_PEGIN_CONTRACT
        );
        bytes32 valueB = PegInDerivation.derivationValue(
            address(0x2222),
            FIXTURE_PEGIN_CONTRACT
        );
        assertTrue(
            valueA != valueB,
            "different rskAddr must derive different values"
        );
    }

    // ---- Negative tests: the two known pitfalls ----

    /// @notice Pitfall #1: keying the redeem-script tag with derivationArgumentsHash directly
    /// (skipping the bridge's address mixing) derives an address the bridge will never re-derive.
    /// On-chain failure mode: -900 FAST_BRIDGE_GENERIC_ERROR at settlement.
    function test_Negative_DirectTagKeyingDivergesFromFixture() public pure {
        bytes memory wrongRedeemScript = PegInDerivation.flyoverRedeemScript(
            PegInDerivation.derivationArgumentsHash(FIXTURE_RSK), // tag used directly: WRONG
            FIXTURE_POWPEG_SCRIPT
        );
        bytes memory wrongPayload = PegInDerivation.depositAddressPayload(
            PegInDerivation.flyoverScriptHash(wrongRedeemScript),
            false
        );
        assertEq(
            wrongPayload,
            PINNED_DIRECT_TAG_PAYLOAD,
            "direct-tag payload drifted from its pin"
        );
        assertTrue(
            keccak256(wrongPayload) != keccak256(PINNED_TESTNET_PAYLOAD),
            "direct-tag keying must NOT produce the expected address"
        );
    }

    /// @notice Pitfall #2: wrapping the (correct) flyover redeem script as a plain P2SH
    /// (HASH160(redeemScript), the pre-segwit federation form) instead of hashing the witness
    /// program derives a different address. On-chain failure mode: -304 VALUE_ZERO at settlement.
    function test_Negative_PlainWrappingDivergesFromFixture() public pure {
        bytes memory wrongPayload = PegInDerivation.depositAddressPayload(
            ripemd160(abi.encodePacked(sha256(PINNED_REDEEM_SCRIPT))),
            false
        );
        assertEq(
            wrongPayload,
            PINNED_PLAIN_WRAP_PAYLOAD,
            "plain-wrap payload drifted from its pin"
        );
        assertTrue(
            keccak256(wrongPayload) != keccak256(PINNED_TESTNET_PAYLOAD),
            "plain wrapping must NOT produce the expected address"
        );
    }

    // ---- Helpers ----

    /// @notice Composes steps 2-4 exactly the way consumers do (see PegInAddressRegistry)
    function _deriveScriptHash() private pure returns (bytes20) {
        bytes32 derivationValue = PegInDerivation.derivationValue(
            FIXTURE_RSK,
            FIXTURE_PEGIN_CONTRACT
        );
        bytes memory redeemScript = PegInDerivation.flyoverRedeemScript(
            derivationValue,
            FIXTURE_POWPEG_SCRIPT
        );
        return PegInDerivation.flyoverScriptHash(redeemScript);
    }
}
