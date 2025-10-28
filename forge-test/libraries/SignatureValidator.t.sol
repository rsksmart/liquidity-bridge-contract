// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {SignatureValidatorWrapper} from "../../contracts/test/SignatureValidatorWrapper.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract SignatureValidatorTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    SignatureValidatorWrapper public signatureValidator;

    address public signer;
    uint256 public signerKey;
    address public otherSigner;
    uint256 public otherSignerKey;

    string public testMessage;
    bytes32 public testMessageHash;

    function setUp() public {
        signatureValidator = new SignatureValidatorWrapper();

        // Create signers with known private keys
        (signer, signerKey) = makeAddrAndKey("signer");
        (otherSigner, otherSignerKey) = makeAddrAndKey("otherSigner");

        testMessage = "Test message for signature validation";
        testMessageHash = keccak256(bytes(testMessage));
    }

    // ============ Valid Signatures Tests ============

    function test_ShouldVerifyAValid65ByteSignature() public view {
        // Sign the message hash (EIP-191 format)
        bytes32 ethSignedMessageHash = testMessageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify signature is 65 bytes
        assertEq(signature.length, 65, "Signature should be 65 bytes");

        // Verify signature
        bool result = signatureValidator.verify(signer, testMessageHash, signature);
        assertTrue(result, "Signature should be valid");
    }

    function test_ShouldReturnFalseForInvalidSignatureWithCorrectLength() public view {
        bytes32 ethSignedMessageHash = testMessageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Use wrong message
        bytes32 wrongMessage = keccak256(bytes("Wrong message"));

        bool result = signatureValidator.verify(signer, wrongMessage, signature);
        assertFalse(result, "Signature should be invalid for wrong message");
    }

    function test_ShouldReturnFalseForSignatureFromDifferentSigner() public view {
        bytes32 ethSignedMessageHash = testMessageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherSignerKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Use signer's address but otherSigner's signature
        bool result = signatureValidator.verify(signer, testMessageHash, signature);
        assertFalse(result, "Signature should be invalid for different signer");
    }

    function test_ShouldCorrectlyVerifyValidSignaturesForNonZeroAddresses() public view {
        // Test with otherSigner to ensure it works with various addresses
        bytes32 ethSignedMessageHash = testMessageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherSignerKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bool result = signatureValidator.verify(otherSigner, testMessageHash, signature);
        assertTrue(result, "Signature should be valid for correct signer");
    }

    function test_ShouldRejectInvalidSignaturesForNonZeroAddresses() public view {
        bytes32 ethSignedMessageHash = testMessageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Use wrong address for the signature
        bool result = signatureValidator.verify(otherSigner, testMessageHash, signature);
        assertFalse(result, "Signature should be invalid for wrong address");
    }

    function test_ShouldHandleSignatureVerificationWithDifferentMessageHashes() public view {
        string memory message1 = "First message";
        string memory message2 = "Second message";
        bytes32 hash1 = keccak256(bytes(message1));
        bytes32 hash2 = keccak256(bytes(message2));

        bytes32 messageBytes1 = hash1.toEthSignedMessageHash();
        bytes32 messageBytes2 = hash2.toEthSignedMessageHash();

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signerKey, messageBytes1);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signerKey, messageBytes2);

        bytes memory signature1 = abi.encodePacked(r1, s1, v1);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        // Verify correct combinations
        assertTrue(signatureValidator.verify(signer, hash1, signature1));
        assertTrue(signatureValidator.verify(signer, hash2, signature2));

        // Verify incorrect combinations
        assertFalse(signatureValidator.verify(signer, hash1, signature2));
        assertFalse(signatureValidator.verify(signer, hash2, signature1));
    }

    // ============ Signature Length Validation Tests ============

    function test_ShouldRevertWithIncorrectSignatureForUndersizedSignature1Byte() public {
        bytes32 messageHash = keccak256(bytes(testMessage));
        bytes memory shortSignature = hex"01";

        vm.expectRevert(
            abi.encodeWithSelector(
                SignatureValidatorWrapper.IncorrectSignature.selector,
                signer,
                messageHash,
                shortSignature
            )
        );
        signatureValidator.verify(signer, messageHash, shortSignature);
    }

    function test_ShouldRevertWithIncorrectSignatureForUndersizedSignature64Bytes() public {
        bytes32 messageHash = keccak256(bytes(testMessage));
        // Create a 64-byte signature (missing 1 byte)
        bytes memory shortSignature = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            shortSignature[i] = 0xaa;
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                SignatureValidatorWrapper.IncorrectSignature.selector,
                signer,
                messageHash,
                shortSignature
            )
        );
        signatureValidator.verify(signer, messageHash, shortSignature);
    }

    function test_ShouldRevertWithIncorrectSignatureForOversizedSignature66Bytes() public {
        bytes32 messageHash = keccak256(bytes(testMessage));
        // Create a 66-byte signature (1 byte too long)
        bytes memory longSignature = new bytes(66);
        for (uint i = 0; i < 66; i++) {
            longSignature[i] = 0xaa;
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                SignatureValidatorWrapper.IncorrectSignature.selector,
                signer,
                messageHash,
                longSignature
            )
        );
        signatureValidator.verify(signer, messageHash, longSignature);
    }

    function test_ShouldRevertWithIncorrectSignatureForEmptySignature() public {
        bytes32 messageHash = keccak256(bytes(testMessage));
        bytes memory emptySignature = hex"";

        vm.expectRevert(
            abi.encodeWithSelector(
                SignatureValidatorWrapper.IncorrectSignature.selector,
                signer,
                messageHash,
                emptySignature
            )
        );
        signatureValidator.verify(signer, messageHash, emptySignature);
    }

    // ============ Zero Address Protection Tests ============

    function test_ShouldRevertWithZeroAddressErrorWhenAddrParameterIsAddressZero() public {
        bytes32 ethSignedMessageHash = testMessageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 messageHash = keccak256(bytes(testMessage));

        vm.expectRevert(SignatureValidatorWrapper.ZeroAddress.selector);
        signatureValidator.verify(address(0), messageHash, signature);
    }

    function test_ShouldPreventZeroAddressBypassAttackVector() public {
        bytes32 messageHash = keccak256(bytes(testMessage));
        bytes32 ethSignedMessageHash = testMessageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Attempt to use zero address should always revert, regardless of signature
        vm.expectRevert(SignatureValidatorWrapper.ZeroAddress.selector);
        signatureValidator.verify(address(0), messageHash, signature);
    }

    function test_ShouldPreventZeroAddressBypassWithEmptySignature() public {
        bytes32 messageHash = keccak256(bytes(testMessage));
        bytes memory emptySignature = hex"";

        // Zero address check should happen before signature length check
        vm.expectRevert(SignatureValidatorWrapper.ZeroAddress.selector);
        signatureValidator.verify(address(0), messageHash, emptySignature);
    }

    function test_ShouldPreventZeroAddressBypassWithMalformedSignature() public {
        // Test with malformed signature data that could cause ecrecover to return zero address
        bytes32 arbitraryHash = keccak256(bytes("malicious data"));
        bytes memory malformedSignature = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c";

        vm.expectRevert(SignatureValidatorWrapper.ZeroAddress.selector);
        signatureValidator.verify(address(0), arbitraryHash, malformedSignature);
    }

    // ============ Edge Cases Tests ============

    function test_ShouldHandleVeryLongSignatureData() public {
        string memory testMsg = "test message";
        bytes32 messageHash = keccak256(bytes(testMsg));

        // Create an overly long signature (should revert due to strict length check)
        bytes32 messageBytes = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, messageBytes);
        bytes memory validSignature = abi.encodePacked(r, s, v);
        bytes memory longSignature = abi.encodePacked(validSignature, hex"deadbeef"); // Add extra data

        vm.expectRevert(
            abi.encodeWithSelector(
                SignatureValidatorWrapper.IncorrectSignature.selector,
                signer,
                messageHash,
                longSignature
            )
        );
        signatureValidator.verify(signer, messageHash, longSignature);
    }

    function test_ShouldHandleShortSignatureDataGracefully() public {
        string memory testMsg = "test message";
        bytes32 messageHash = keccak256(bytes(testMsg));
        bytes memory shortSignature = hex"1234"; // Too short to be a valid signature

        // Should revert with IncorrectSignature due to strict length check
        vm.expectRevert(
            abi.encodeWithSelector(
                SignatureValidatorWrapper.IncorrectSignature.selector,
                signer,
                messageHash,
                shortSignature
            )
        );
        signatureValidator.verify(signer, messageHash, shortSignature);
    }
}
