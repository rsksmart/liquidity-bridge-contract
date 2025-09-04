import { expect } from "chai";
import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { SignatureValidator } from "../typechain-types";

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

  describe("Zero address protection", function () {
    it("should revert with ZeroAddress when addr is zero address", async function () {
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      const signature = await signer.signMessage(testMessageHash);

      await expect(
        signatureValidator.verify(ethers.ZeroAddress, messageHash, signature)
      ).to.be.revertedWithCustomError(signatureValidator, "ZeroAddress");
    });

    it("should revert with ZeroAddress before signature length checks", async function () {
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      const malformedSignature = "0x1234";

      await expect(
        signatureValidator.verify(
          ethers.ZeroAddress,
          messageHash,
          malformedSignature
        )
      ).to.be.revertedWithCustomError(signatureValidator, "ZeroAddress");
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
    });
  });
});
