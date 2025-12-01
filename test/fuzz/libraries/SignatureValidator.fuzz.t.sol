// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {SignatureValidatorWrapper} from "../../../src/test/SignatureValidatorWrapper.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title SignatureValidator Fuzz Tests
/// @notice Fuzz tests for signature validation to ensure robustness against malformed inputs
contract SignatureValidatorFuzzTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    SignatureValidatorWrapper public signatureValidator;

    address public signer;
    uint256 public signerKey;

    function setUp() public {
        signatureValidator = new SignatureValidatorWrapper();
        (signer, signerKey) = makeAddrAndKey("signer");
    }

    /// @notice Fuzz test: Valid signatures should always verify correctly
    function testFuzz_Verify_AcceptsValidSignatures(
        bytes32 messageHash
    ) public view {
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        bool result = signatureValidator.verify(signer, messageHash, signature);
        assertTrue(result, "Valid signature should verify");
    }

    /// @notice Fuzz test: Wrong message hash should fail verification
    function testFuzz_Verify_RejectsWrongMessageHash(
        bytes32 correctHash,
        bytes32 wrongHash
    ) public view {
        vm.assume(correctHash != wrongHash);

        bytes32 ethSignedMessageHash = correctHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        bool result = signatureValidator.verify(signer, wrongHash, signature);
        assertFalse(result, "Signature with wrong hash should not verify");
    }

    /// @notice Fuzz test: Wrong signer address should fail verification
    function testFuzz_Verify_RejectsWrongSigner(
        bytes32 messageHash,
        address wrongSigner
    ) public view {
        vm.assume(wrongSigner != signer);
        vm.assume(wrongSigner != address(0));

        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        bool result = signatureValidator.verify(
            wrongSigner,
            messageHash,
            signature
        );
        assertFalse(result, "Signature with wrong signer should not verify");
    }

    /// @notice Fuzz test: Invalid signature lengths should revert
    function testFuzz_Verify_RevertsOnInvalidLength(
        bytes32 messageHash,
        uint8 length
    ) public {
        vm.assume(length != 65);
        vm.assume(length <= 200); // Bound to reasonable size

        bytes memory invalidSignature = new bytes(length);

        vm.expectRevert(
            abi.encodeWithSelector(
                SignatureValidatorWrapper.IncorrectSignature.selector,
                signer,
                messageHash,
                invalidSignature
            )
        );
        signatureValidator.verify(signer, messageHash, invalidSignature);
    }

    /// @notice Fuzz test: Malformed signature bytes should not verify
    function testFuzz_Verify_RejectsMalformedSignatures(
        bytes32 messageHash,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) public view {
        // Only test invalid v values (valid are 27, 28)
        vm.assume(v != 27 && v != 28);

        bytes memory signature = abi.encodePacked(r, s, v);

        // Invalid signatures may either return false or revert with ECDSAInvalidSignature
        try signatureValidator.verify(signer, messageHash, signature) returns (
            bool result
        ) {
            assertFalse(result, "Malformed signature should not verify");
        } catch {
            // It's acceptable to revert on malformed signatures
        }
    }

    /// @notice Fuzz test: Zero address should always revert
    function testFuzz_Verify_RevertsOnZeroAddress(
        bytes32 messageHash,
        bytes memory signature
    ) public {
        // Bound signature length to avoid other reverts
        vm.assume(signature.length == 65);

        vm.expectRevert(SignatureValidatorWrapper.ZeroAddress.selector);
        signatureValidator.verify(address(0), messageHash, signature);
    }

    /// @notice Fuzz test: Signature with all zeros should not verify
    function testFuzz_Verify_RejectsZeroSignature(
        bytes32 messageHash
    ) public view {
        bytes memory zeroSignature = new bytes(65);

        // Zero signatures may either return false or revert with ECDSAInvalidSignature
        try
            signatureValidator.verify(signer, messageHash, zeroSignature)
        returns (bool result) {
            assertFalse(result, "All-zero signature should not verify");
        } catch {
            // It's acceptable to revert on zero signatures
        }
    }

    /// @notice Fuzz test: Modified signature components should fail
    function testFuzz_Verify_RejectsModifiedSignature(
        bytes32 messageHash,
        uint8 rModifier,
        uint8 sModifier,
        uint8 vModifier
    ) public view {
        vm.assume(rModifier != 0 || sModifier != 0 || vModifier != 0);

        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerKey,
            ethSignedMessageHash
        );

        // Modify signature components
        bytes32 modifiedR = bytes32(uint256(r) ^ uint256(rModifier));
        bytes32 modifiedS = bytes32(uint256(s) ^ uint256(sModifier));
        uint8 modifiedV = v ^ vModifier;

        bytes memory modifiedSignature = abi.encodePacked(
            modifiedR,
            modifiedS,
            modifiedV
        );

        // Modified signatures may either return false or revert with ECDSAInvalidSignature
        try
            signatureValidator.verify(signer, messageHash, modifiedSignature)
        returns (bool result) {
            assertFalse(result, "Modified signature should not verify");
        } catch {
            // It's acceptable to revert on invalid signatures
        }
    }

    /// @notice Fuzz test: Replay across different message hashes should fail
    function testFuzz_Verify_PreventsReplayAcrossDifferentMessages(
        bytes32 messageHash1,
        bytes32 messageHash2
    ) public view {
        vm.assume(messageHash1 != messageHash2);

        // Sign first message
        bytes32 ethSignedMessageHash1 = messageHash1.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerKey,
            ethSignedMessageHash1
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Try to use signature for second message
        bool result = signatureValidator.verify(
            signer,
            messageHash2,
            signature
        );
        assertFalse(
            result,
            "Signature should not be replayable across different messages"
        );
    }

    /// @notice Fuzz test: Signature malleability with high s values
    function testFuzz_Verify_HandlesMalleableSignatures(
        bytes32 messageHash
    ) public view {
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerKey,
            ethSignedMessageHash
        );

        // Try to create malleable signature (flip s and v)
        // secp256k1 curve order
        bytes32 secp256k1N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 malleableS = bytes32(uint256(secp256k1N) - uint256(s));
        uint8 malleableV = v == 27 ? 28 : 27;

        bytes memory malleableSignature = abi.encodePacked(
            r,
            malleableS,
            malleableV
        );

        // Modern ECDSA should reject high-s values (or both should verify to same address)
        // We verify that the signature either fails or verifies to the correct signer
        try
            signatureValidator.verify(signer, messageHash, malleableSignature)
        returns (bool result) {
            // If it doesn't revert, it should still verify correctly
            assertTrue(
                result,
                "Malleable signature should either revert or verify correctly"
            );
        } catch {
            // It's acceptable to revert on malleable signatures
        }
    }

    /// @notice Fuzz test: Different signers with same message should produce different signatures
    function testFuzz_Verify_DifferentSignersProduceDifferentSignatures(
        bytes32 messageHash,
        uint256 privateKey1,
        uint256 privateKey2
    ) public view {
        // Bound private keys to valid range
        privateKey1 = bound(
            privateKey1,
            1,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140
        );
        privateKey2 = bound(
            privateKey2,
            1,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140
        );
        vm.assume(privateKey1 != privateKey2);

        address addr1 = vm.addr(privateKey1);
        address addr2 = vm.addr(privateKey2);
        vm.assume(addr1 != address(0) && addr2 != address(0));

        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

        // Test signature 1
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                privateKey1,
                ethSignedMessageHash
            );
            bytes memory signature = abi.encodePacked(r, s, v);

            // Signature 1 should verify for addr1, not addr2
            assertTrue(
                signatureValidator.verify(addr1, messageHash, signature)
            );
            assertFalse(
                signatureValidator.verify(addr2, messageHash, signature)
            );
        }

        // Test signature 2
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                privateKey2,
                ethSignedMessageHash
            );
            bytes memory signature = abi.encodePacked(r, s, v);

            // Signature 2 should verify for addr2, not addr1
            assertTrue(
                signatureValidator.verify(addr2, messageHash, signature)
            );
            assertFalse(
                signatureValidator.verify(addr1, messageHash, signature)
            );
        }
    }
}
