import { expect } from "chai";
import { ethers } from "hardhat";
import { SignatureValidator } from "../typechain-types";
import { deployContract } from "../scripts/deployment-utils/utils";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import hre from "hardhat";

describe("SignatureValidator", function () {
  let signatureValidator: SignatureValidator;
  let signer: HardhatEthersSigner;
  let testMessage: string;
  let testMessageHash: Uint8Array;

  beforeEach(async function () {
    const SignatureValidatorFactory = await ethers.getContractFactory(
      "SignatureValidator"
    );
    signatureValidator = await SignatureValidatorFactory.deploy();

    [signer] = await ethers.getSigners();
    testMessage = "Test message for signature validation";
    testMessageHash = ethers.getBytes(
      ethers.keccak256(ethers.toUtf8Bytes(testMessage))
    );
  });

  describe("Valid signatures", function () {
    it("should verify a valid 65-byte signature", async function () {
      const signature = await signer.signMessage(testMessageHash);

      expect(signature).to.have.lengthOf(132); // 65 bytes * 2 (hex) + "0x" prefix

      const result = await signatureValidator.verify(
        signer.address,
        ethers.keccak256(ethers.toUtf8Bytes(testMessage)),
        signature
      );

      expect(result).to.equal(true);
    });

    it("should return false for invalid signature with correct length", async function () {
      const signature = await signer.signMessage(testMessageHash);
      const wrongMessage = ethers.keccak256(
        ethers.toUtf8Bytes("Wrong message")
      );

      const result = await signatureValidator.verify(
        signer.address,
        wrongMessage,
        signature
      );

      expect(result).to.equal(false);
    });

    it("should return false for signature from different signer", async function () {
      const [, otherSigner] = await ethers.getSigners();
      const signature = await otherSigner.signMessage(testMessageHash);

      const result = await signatureValidator.verify(
        signer.address, // Different from otherSigner
        ethers.keccak256(ethers.toUtf8Bytes(testMessage)),
        signature
      );

      expect(result).to.equal(false);
    });
  });

  describe("Signature length validation", function () {
    it("should revert with IncorrectSignature for undersized signature (1 byte)", async function () {
      const truncatedSignature = "0x01";
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));

      await expect(
        signatureValidator.verify(
          signer.address,
          messageHash,
          truncatedSignature
        )
      )
        .to.be.revertedWithCustomError(signatureValidator, "IncorrectSignature")
        .withArgs(signer.address, messageHash, truncatedSignature);
    });

    it("should revert with IncorrectSignature for undersized signature (64 bytes)", async function () {
      const truncatedSignature = "0x" + "01".repeat(64); // 64 bytes, just one short
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));

      await expect(
        signatureValidator.verify(
          signer.address,
          messageHash,
          truncatedSignature
        )
      )
        .to.be.revertedWithCustomError(signatureValidator, "IncorrectSignature")
        .withArgs(signer.address, messageHash, truncatedSignature);
    });

    it("should revert with IncorrectSignature for oversized signature (66 bytes)", async function () {
      const oversizedSignature = "0x" + "01".repeat(66); // 66 bytes
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));

      await expect(
        signatureValidator.verify(
          signer.address,
          messageHash,
          oversizedSignature
        )
      )
        .to.be.revertedWithCustomError(signatureValidator, "IncorrectSignature")
        .withArgs(signer.address, messageHash, oversizedSignature);
    });

    it("should revert with IncorrectSignature for empty signature", async function () {
      const emptySignature = "0x";
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));

      await expect(
        signatureValidator.verify(signer.address, messageHash, emptySignature)
      )
        .to.be.revertedWithCustomError(signatureValidator, "IncorrectSignature")
        .withArgs(signer.address, messageHash, emptySignature);
=======

describe("SignatureValidator", () => {
  let signatureValidator: SignatureValidator;
  let signer: HardhatEthersSigner;
  let otherSigner: HardhatEthersSigner;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    signer = signers[0];
    otherSigner = signers[1];

    const deploymentInfo = await deployContract(
      "SignatureValidator",
      hre.network.name
    );
    signatureValidator = await ethers.getContractAt(
      "SignatureValidator",
      deploymentInfo.address
    );
  });

  describe("Zero Address Protection", () => {
    it("should revert with ZeroAddress error when addr parameter is address(0)", async () => {
      const testMessage = "test message";
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      const signature = await signer.signMessage(ethers.getBytes(messageHash));

      // Attempt to verify with zero address should revert
      await expect(
        signatureValidator.verify(ethers.ZeroAddress, messageHash, signature)
      ).to.be.revertedWithCustomError(signatureValidator, "ZeroAddress");
    });

    it("should prevent zero address bypass attack vector", async () => {
      // This test demonstrates that the attack vector described is now prevented
      // An attacker cannot pass address(0) and arbitrary invalid signature data
      // to bypass authentication

      const arbitraryHash = ethers.keccak256(
        ethers.toUtf8Bytes("malicious data")
      );
      const invalidSignature =
        "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12";

      // Before the fix, this would have returned true, allowing the attack
      // Now it should revert with ZeroAddress error, preventing the attack
      await expect(
        signatureValidator.verify(
          ethers.ZeroAddress,
          arbitraryHash,
          invalidSignature
        )
      ).to.be.revertedWithCustomError(signatureValidator, "ZeroAddress");
    });

    it("should prevent zero address bypass with empty signature", async () => {
      // Another variation of the attack with empty signature
      const arbitraryHash = ethers.keccak256(
        ethers.toUtf8Bytes("malicious data")
      );
      const emptySignature = "0x";

      await expect(
        signatureValidator.verify(
          ethers.ZeroAddress,
          arbitraryHash,
          emptySignature
        )
      ).to.be.revertedWithCustomError(signatureValidator, "ZeroAddress");
    });

    it("should prevent zero address bypass with malformed signature", async () => {
      // Test with malformed signature data that could cause ecrecover to return zero address
      const arbitraryHash = ethers.keccak256(
        ethers.toUtf8Bytes("malicious data")
      );
      const malformedSignature =
        "0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c";

      await expect(
        signatureValidator.verify(
          ethers.ZeroAddress,
          arbitraryHash,
          malformedSignature
        )
      ).to.be.revertedWithCustomError(signatureValidator, "ZeroAddress");
    });
  });

  describe("Valid Signature Verification", () => {
    it("should correctly verify valid signatures for non-zero addresses", async () => {
      const testMessage = "test message for signature";
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      const messageBytes = ethers.getBytes(messageHash);

      // Sign the message hash with the signer
      const signature = await signer.signMessage(messageBytes);

      // Verify the signature should return true for the correct signer address
      const isValid = await signatureValidator.verify(
        signer.address,
        messageHash,
        signature
      );
      expect(isValid).to.equal(true);
    });

    it("should reject invalid signatures for non-zero addresses", async () => {
      const testMessage = "test message for signature";
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      const messageBytes = ethers.getBytes(messageHash);

      // Sign with one signer
      const signature = await signer.signMessage(messageBytes);

      // Try to verify with different signer's address should return false
      const isValid = await signatureValidator.verify(
        otherSigner.address,
        messageHash,
        signature
      );
      expect(isValid).to.equal(false);
    });

    it("should handle signature verification with different message hashes", async () => {
      const originalMessage = "original message";
      const differentMessage = "different message";

      const originalHash = ethers.keccak256(
        ethers.toUtf8Bytes(originalMessage)
      );
      const differentHash = ethers.keccak256(
        ethers.toUtf8Bytes(differentMessage)
      );

      const originalBytes = ethers.getBytes(originalHash);
      const signature = await signer.signMessage(originalBytes);

      // Should return true for original hash
      const validOriginal = await signatureValidator.verify(
        signer.address,
        originalHash,
        signature
      );
      expect(validOriginal).to.equal(true);

      // Should return false for different hash
      const validDifferent = await signatureValidator.verify(
        signer.address,
        differentHash,
        signature
      );
      expect(validDifferent).to.equal(false);
    });
  });

  describe("Edge Cases", () => {
    it("should handle very long signature data", async () => {
      const testMessage = "test message";
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));

      // Create an overly long signature (should still work if first 65 bytes are valid)
      const messageBytes = ethers.getBytes(messageHash);
      const validSignature = await signer.signMessage(messageBytes);
      const longSignature = validSignature + "deadbeef"; // Add extra data

      const isValid = await signatureValidator.verify(
        signer.address,
        messageHash,
        longSignature
      );
      expect(isValid).to.equal(true);
    });

    it("should handle short signature data gracefully", async () => {
      const testMessage = "test message";
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      const shortSignature = "0x1234"; // Too short to be a valid signature

      // Should not revert but return false (ecrecover will return zero address, but we check for non-zero signer)
      const isValid = await signatureValidator.verify(
        signer.address,
        messageHash,
        shortSignature
      );
      expect(isValid).to.equal(false);
    });
  });
});
