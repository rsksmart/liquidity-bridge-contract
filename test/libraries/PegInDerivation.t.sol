// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {OpCodes} from "@rsksmart/btc-transaction-solidity-helper/contracts/OpCodes.sol";
import {PegInDerivation} from "../../src/libraries/PegInDerivation.sol";

/// @title PegInDerivation Library Tests
/// @notice Pins the derivation vectors as FIXED-BYTE fixtures, PER NETWORK, and encodes the two
/// known derivation pitfalls as negative tests.
/// @dev Every expected value below is a pinned constant computed once offline by an independent
/// implementation of the scheme (keccak256/sha256/ripemd160 outside Solidity), never by calling the
/// library under test. Nothing is recomputed from the library's own constants: if any constant,
/// opcode, or version byte changes, these tests fail. That is the point.
///
/// The SHAPE of the scheme was validated end-to-end on a live regtest against the unmodified powpeg
/// bridge (rskj 9.0.2, 2026-06-30, settle tx
/// 0x174ab0df7cc86648a40d9b36da95fd4dacf2f18c135606141d532b7d1363c7de). That run used a real regtest
/// p2pkh for the two BTC placeholders; the placeholders are now the per-network ZERO address
/// (FLY-2521), which rotated every vector below. No end-to-end run has settled with the zero
/// placeholders yet — the settlement path does not exist on this branch — so these fixtures pin the
/// derivation, not the bridge's acceptance of a zero-hash address.
contract PegInDerivationTest is Test {
    // ---- Fixture inputs (the PoC vector) ----

    /// @notice The RSK destination address of the pinned vector
    address internal constant FIXTURE_RSK =
        0x0000000000000000000000000000000000000aBc;

    /// @notice The PegInContract (lbcAddress) mixed into the pinned vector
    address internal constant FIXTURE_PEGIN_CONTRACT =
        0x00000000000000000000000000000000C0FFEE01;

    /// @notice The active powpeg redeem script of the pinned vector (the PoC bridge-mock script)
    bytes internal constant FIXTURE_POWPEG_SCRIPT =
        hex"522102cd53fc53a07f211641a677d250f6de99caf620e8e77071e811a28b3bcddf0be1210362634ab5"
        hex"7dae9cb373a5d536e66a8c4f67468bbcfb063809bab643072d78a1242103c5946b3fbae03a654237da86"
        hex"3c9ed534e0878657175b132b8ca630f245df04db53ae";

    // ---- Pinned protocol constants ----

    /// @notice The exact bytes of DERIVATION_DOMAIN ("FLYOVER_PEGIN_V1")
    bytes internal constant PINNED_DOMAIN =
        hex"464c594f5645525f504547494e5f5631";

    /// @notice The 21-byte testnet/regtest zero placeholder: version 0x6f ++ 20 zero bytes
    bytes internal constant PINNED_BITCOIN_ZERO_ADDRESS_TESTNET =
        hex"6f0000000000000000000000000000000000000000";

    /// @notice The 21-byte mainnet zero placeholder: version 0x00 ++ 20 zero bytes
    bytes internal constant PINNED_BITCOIN_ZERO_ADDRESS_MAINNET =
        hex"000000000000000000000000000000000000000000";

    // ---- Pinned step outputs, TESTNET/REGTEST (computed once offline, frozen) ----

    /// @notice Step 1: keccak256(DERIVATION_DOMAIN ++ rskAddr). Network-independent: the
    /// placeholders enter at step 2, not step 1.
    bytes32 internal constant PINNED_ARGS_HASH =
        0x0ac85b6d14264cdf09e4b64c6250b2fb650d8d87f04164e8f0c69b1f29e1a89a;

    /// @notice Step 2 (testnet): keccak256(argsHash ++ p ++ bytes20(pegInContract) ++ p)
    bytes32 internal constant PINNED_DERIVATION_VALUE_TESTNET =
        0x6ca7b4e64cad153fbd1ddfda69945f982f204c662da0a904367b9ca593b42a9b;

    /// @notice Step 3 (testnet): OP_PUSHBYTES_32 ++ derivationValue ++ OP_DROP ++ powpeg script
    bytes internal constant PINNED_REDEEM_SCRIPT_TESTNET =
        hex"206ca7b4e64cad153fbd1ddfda69945f982f204c662da0a904367b9ca593b42a9b75522102cd53fc"
        hex"53a07f211641a677d250f6de99caf620e8e77071e811a28b3bcddf0be1210362634ab57dae9cb373"
        hex"a5d536e66a8c4f67468bbcfb063809bab643072d78a1242103c5946b3fbae03a654237da863c9ed5"
        hex"34e0878657175b132b8ca630f245df04db53ae";

    /// @notice Step 4 (testnet): HASH160 of the flyover redeem script
    bytes20 internal constant PINNED_SCRIPT_HASH_TESTNET =
        bytes20(hex"0c63443c601c577510e7f80cdd7f663e075dc07e");

    /// @notice Step 5a (testnet): OP_HASH160 0x14 <scriptHash> OP_EQUAL
    bytes internal constant PINNED_SCRIPT_PUBKEY_TESTNET =
        hex"a9140c63443c601c577510e7f80cdd7f663e075dc07e87";

    /// @notice Step 5b (testnet): 0xC4 ++ scriptHash ++ checksum
    bytes internal constant PINNED_TESTNET_PAYLOAD =
        hex"c40c63443c601c577510e7f80cdd7f663e075dc07e862c627a";

    // ---- Pinned step outputs, MAINNET ----

    /// @notice Step 2 (mainnet). Differs from the testnet value because the placeholders differ in
    /// their version byte, so EVERY downstream mainnet vector differs too — not just the address
    /// version byte.
    bytes32 internal constant PINNED_DERIVATION_VALUE_MAINNET =
        0x5f711554b557c7fa5da3126a212b7ef7ed5db9425be5eb872230eb1b356d235b;

    /// @notice Step 3 (mainnet)
    bytes internal constant PINNED_REDEEM_SCRIPT_MAINNET =
        hex"205f711554b557c7fa5da3126a212b7ef7ed5db9425be5eb872230eb1b356d235b75522102cd53fc"
        hex"53a07f211641a677d250f6de99caf620e8e77071e811a28b3bcddf0be1210362634ab57dae9cb373"
        hex"a5d536e66a8c4f67468bbcfb063809bab643072d78a1242103c5946b3fbae03a654237da863c9ed5"
        hex"34e0878657175b132b8ca630f245df04db53ae";

    /// @notice Step 4 (mainnet)
    bytes20 internal constant PINNED_SCRIPT_HASH_MAINNET =
        bytes20(hex"d8c7225ff79f803c7cbaed672f764c639133c3fd");

    /// @notice Step 5a (mainnet)
    bytes internal constant PINNED_SCRIPT_PUBKEY_MAINNET =
        hex"a914d8c7225ff79f803c7cbaed672f764c639133c3fd87";

    /// @notice Step 5b (mainnet): 0x05 ++ scriptHash ++ checksum
    bytes internal constant PINNED_MAINNET_PAYLOAD =
        hex"05d8c7225ff79f803c7cbaed672f764c639133c3fd6a67b0eb";

    // ---- Pinned negative-form payloads (the two on-chain failure modes) ----

    /// @notice Pitfall #1 (-900): payload derived keying the redeem-script tag with the
    /// derivationArgumentsHash DIRECTLY, skipping step 2's address mixing. Unchanged by FLY-2521:
    /// this form never mixes the placeholders at all.
    bytes internal constant PINNED_DIRECT_TAG_PAYLOAD =
        hex"c4b0275b8861bb9b30585453cde8d9efaa99b444487e6c335a";

    /// @notice Pitfall #2 (-304): payload derived wrapping the CORRECT testnet redeem script as a
    /// segwit P2SH-of-P2WSH instead of a plain P2SH
    bytes internal constant PINNED_SEGWIT_PAYLOAD =
        hex"c490a45e9bf80f1a2d9aac68ef224d929bb9b507d8545026ec";

    // ---- Constant pinning ----

    function test_DomainConstantIsPinned() public pure {
        assertEq(
            PegInDerivation.DERIVATION_DOMAIN,
            PINNED_DOMAIN,
            "DERIVATION_DOMAIN changed"
        );
    }

    function test_RefundPlaceholderIsPinned() public pure {
        _assertZeroPlaceholder(
            PegInDerivation.getRefundPlaceholderBtcAddress(false),
            PINNED_BITCOIN_ZERO_ADDRESS_TESTNET,
            bytes1(0x6f),
            "refund testnet"
        );
        _assertZeroPlaceholder(
            PegInDerivation.getRefundPlaceholderBtcAddress(true),
            PINNED_BITCOIN_ZERO_ADDRESS_MAINNET,
            bytes1(0x00),
            "refund mainnet"
        );
    }

    function test_LpPlaceholderIsPinned() public pure {
        _assertZeroPlaceholder(
            PegInDerivation.getLpPlaceholderBtcAddress(false),
            PINNED_BITCOIN_ZERO_ADDRESS_TESTNET,
            bytes1(0x6f),
            "lp testnet"
        );
        _assertZeroPlaceholder(
            PegInDerivation.getLpPlaceholderBtcAddress(true),
            PINNED_BITCOIN_ZERO_ADDRESS_MAINNET,
            bytes1(0x00),
            "lp mainnet"
        );
    }

    /// @notice The two networks' placeholders must differ EXACTLY in the version byte — the whole
    /// reason the placeholders became network-dependent.
    function test_PlaceholdersDifferOnlyInVersionByte() public pure {
        bytes memory testnetPlaceholder = PegInDerivation.getRefundPlaceholderBtcAddress(false);
        bytes memory mainnetPlaceholder = PegInDerivation.getRefundPlaceholderBtcAddress(true);
        assertTrue(
            testnetPlaceholder[0] != mainnetPlaceholder[0],
            "version byte must differ between networks"
        );
        for (uint256 i = 1; i < 21; ++i) {
            assertEq(
                testnetPlaceholder[i],
                mainnetPlaceholder[i],
                "only the version byte may differ"
            );
        }
        assertEq(
            keccak256(PegInDerivation.getLpPlaceholderBtcAddress(false)),
            keccak256(testnetPlaceholder),
            "lp/refund testnet placeholders must match"
        );
        assertEq(
            keccak256(PegInDerivation.getLpPlaceholderBtcAddress(true)),
            keccak256(mainnetPlaceholder),
            "lp/refund mainnet placeholders must match"
        );
    }

    // ---- Per-step fixtures (each step fed the PINNED previous output) ----

    function test_Step1_DerivationArgumentsHash() public pure {
        assertEq(
            PegInDerivation.derivationArgumentsHash(FIXTURE_RSK),
            PINNED_ARGS_HASH,
            "step 1 drifted"
        );
    }

    function test_Step2_DerivationValue_Testnet() public pure {
        assertEq(
            PegInDerivation.derivationValue(
                FIXTURE_RSK,
                FIXTURE_PEGIN_CONTRACT,
                false
            ),
            PINNED_DERIVATION_VALUE_TESTNET,
            "step 2 testnet drifted"
        );
    }

    function test_Step2_DerivationValue_Mainnet() public pure {
        assertEq(
            PegInDerivation.derivationValue(
                FIXTURE_RSK,
                FIXTURE_PEGIN_CONTRACT,
                true
            ),
            PINNED_DERIVATION_VALUE_MAINNET,
            "step 2 mainnet drifted"
        );
    }

    /// @notice The per-network placeholders must make step 2 itself network-dependent. If this
    /// fails, the two networks share a derived address set.
    function test_Step2_NetworksDeriveDifferentValues() public pure {
        assertTrue(
            PINNED_DERIVATION_VALUE_TESTNET != PINNED_DERIVATION_VALUE_MAINNET,
            "pinned per-network values must differ"
        );
        assertTrue(
            PegInDerivation.derivationValue(
                FIXTURE_RSK,
                FIXTURE_PEGIN_CONTRACT,
                false
            ) !=
                PegInDerivation.derivationValue(
                    FIXTURE_RSK,
                    FIXTURE_PEGIN_CONTRACT,
                    true
                ),
            "mainnet flag must change the derivation value"
        );
    }

    function test_Step3_FlyoverRedeemScript_Testnet() public pure {
        assertEq(
            PegInDerivation.flyoverRedeemScript(
                PINNED_DERIVATION_VALUE_TESTNET,
                FIXTURE_POWPEG_SCRIPT
            ),
            PINNED_REDEEM_SCRIPT_TESTNET,
            "step 3 testnet drifted"
        );
    }

    function test_Step3_FlyoverRedeemScript_Mainnet() public pure {
        assertEq(
            PegInDerivation.flyoverRedeemScript(
                PINNED_DERIVATION_VALUE_MAINNET,
                FIXTURE_POWPEG_SCRIPT
            ),
            PINNED_REDEEM_SCRIPT_MAINNET,
            "step 3 mainnet drifted"
        );
    }

    function test_Step4_FlyoverScriptHash_Testnet() public pure {
        assertEq(
            PegInDerivation.flyoverScriptHash(PINNED_REDEEM_SCRIPT_TESTNET),
            PINNED_SCRIPT_HASH_TESTNET,
            "step 4 testnet drifted"
        );
    }

    function test_Step4_FlyoverScriptHash_Mainnet() public pure {
        assertEq(
            PegInDerivation.flyoverScriptHash(PINNED_REDEEM_SCRIPT_MAINNET),
            PINNED_SCRIPT_HASH_MAINNET,
            "step 4 mainnet drifted"
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
            PegInDerivation.depositAddressPayload(
                PINNED_SCRIPT_HASH_TESTNET,
                false
            ),
            PINNED_TESTNET_PAYLOAD,
            "step 5b testnet drifted"
        );
    }

    function test_Step5b_MainnetPayload() public pure {
        assertEq(
            PegInDerivation.depositAddressPayload(
                PINNED_SCRIPT_HASH_MAINNET,
                true
            ),
            PINNED_MAINNET_PAYLOAD,
            "step 5b mainnet drifted"
        );
    }

    // ---- Full chain, composed the way consumers compose it ----

    function test_FullChainMatchesPinnedFixtures() public pure {
        assertEq(
            PegInDerivation.depositAddressPayload(
                _deriveScriptHash(false),
                false
            ),
            PINNED_TESTNET_PAYLOAD,
            "full-chain testnet payload drifted"
        );
        assertEq(
            PegInDerivation.depositAddressPayload(
                _deriveScriptHash(true),
                true
            ),
            PINNED_MAINNET_PAYLOAD,
            "full-chain mainnet payload drifted"
        );
    }

    /// @notice The networks derive genuinely different script hashes, so a mainnet address is not a
    /// re-prefixed testnet address.
    function test_FullChainNetworksDeriveDifferentScriptHashes() public pure {
        assertTrue(
            _deriveScriptHash(false) != _deriveScriptHash(true),
            "networks must derive different script hashes"
        );
    }

    function test_DerivationIsDeterministic() public pure {
        assertEq(
            _deriveScriptHash(false),
            _deriveScriptHash(false),
            "same inputs must derive the same script hash"
        );
    }

    function test_DifferentRskAddressesDeriveDifferentAddresses() public pure {
        bytes32 valueA = PegInDerivation.derivationValue(
            address(0x1111),
            FIXTURE_PEGIN_CONTRACT,
            false
        );
        bytes32 valueB = PegInDerivation.derivationValue(
            address(0x2222),
            FIXTURE_PEGIN_CONTRACT,
            false
        );
        assertTrue(
            valueA != valueB,
            "different rskAddr must derive different values"
        );
    }

    // ---- Negative tests: the two known pitfalls (walkthrough 3-D) ----

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
            "direct-tag keying must NOT produce the correct address"
        );
    }

    /// @notice Pitfall #2: wrapping the (correct) flyover redeem script as a segwit P2SH-of-P2WSH
    /// (HASH160(OP_0 OP_PUSHBYTES_32 sha256(redeemScript))) instead of a plain P2SH derives a
    /// different address. On-chain failure mode: -304 VALUE_ZERO at settlement.
    function test_Negative_SegwitWrappingDivergesFromFixture() public pure {
        bytes memory segwitScript = bytes.concat(
            OpCodes.OP_0,
            OpCodes.OP_PUSHBYTES_32,
            sha256(PINNED_REDEEM_SCRIPT_TESTNET)
        );
        bytes memory wrongPayload = PegInDerivation.depositAddressPayload(
            PegInDerivation.flyoverScriptHash(segwitScript),
            false
        );
        assertEq(
            wrongPayload,
            PINNED_SEGWIT_PAYLOAD,
            "segwit payload drifted from its pin"
        );
        assertTrue(
            keccak256(wrongPayload) != keccak256(PINNED_TESTNET_PAYLOAD),
            "segwit wrapping must NOT produce the correct address"
        );
    }

    // ---- Helpers ----

    /// @notice Asserts a placeholder is exactly `version ++ 20 zero bytes` and matches its pin
    function _assertZeroPlaceholder(
        bytes memory placeholder,
        bytes memory pinned,
        bytes1 version,
        string memory label
    ) private pure {
        assertEq(
            placeholder.length,
            21,
            string.concat(label, ": must be 21 bytes (version ++ HASH160)")
        );
        assertEq(
            placeholder[0],
            version,
            string.concat(label, ": wrong version byte")
        );
        for (uint256 i = 1; i < 21; ++i) {
            assertEq(
                placeholder[i],
                bytes1(0x00),
                string.concat(label, ": HASH160 must be all zeroes")
            );
        }
        assertEq(
            placeholder,
            pinned,
            string.concat(label, ": placeholder changed")
        );
    }

    /// @notice Composes steps 2-4 exactly the way consumers do (see PegInAddressRegistry)
    function _deriveScriptHash(bool isMainnet) private pure returns (bytes20) {
        bytes32 derivationValue = PegInDerivation.derivationValue(
            FIXTURE_RSK,
            FIXTURE_PEGIN_CONTRACT,
            isMainnet
        );
        bytes memory redeemScript = PegInDerivation.flyoverRedeemScript(
            derivationValue,
            FIXTURE_POWPEG_SCRIPT
        );
        return PegInDerivation.flyoverScriptHash(redeemScript);
    }
}
