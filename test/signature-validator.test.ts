import { expect } from "chai";
import { ethers } from "hardhat";
import { SignatureValidatorWrapper } from "../typechain-types";
import { deployLibraries } from "../scripts/deployment-utils/deploy-libraries";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import hre from "hardhat";

describe("SignatureValidator", function () {
  let signatureValidator: SignatureValidatorWrapper;
  let signer: HardhatEthersSigner;
  let otherSigner: HardhatEthersSigner;
  let testMessage: string;
  let testMessageHash: Uint8Array;

  beforeEach(async function () {
    const libraries = await deployLibraries(
      hre.network.name,
      "SignatureValidator"
    );

    const SignatureValidatorWrapper = await ethers.getContractFactory(
      "SignatureValidatorWrapper",
      {
        libraries: {
          SignatureValidator: libraries.SignatureValidator.address,
        },
      }
    );
    signatureValidator = await SignatureValidatorWrapper.deploy();
    await signatureValidator.waitForDeployment();

    const signers = await ethers.getSigners();
    signer = signers[0];
    otherSigner = signers[1];

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
      const signature = await otherSigner.signMessage(testMessageHash);

      const result = await signatureValidator.verify(
        signer.address, // Using signer's address but otherSigner's signature
        ethers.keccak256(ethers.toUtf8Bytes(testMessage)),
        signature
      );

      expect(result).to.equal(false);
    });

    it("should correctly verify valid signatures for non-zero addresses", async function () {
      // Test with a different signer to ensure it works with various addresses
      const signature = await otherSigner.signMessage(testMessageHash);

      const result = await signatureValidator.verify(
        otherSigner.address,
        ethers.keccak256(ethers.toUtf8Bytes(testMessage)),
        signature
      );

      expect(result).to.equal(true);
    });

    it("should reject invalid signatures for non-zero addresses", async function () {
      const signature = await signer.signMessage(testMessageHash);

      const result = await signatureValidator.verify(
        otherSigner.address, // Wrong address for the signature
        ethers.keccak256(ethers.toUtf8Bytes(testMessage)),
        signature
      );

      expect(result).to.equal(false);
    });

    it("should handle signature verification with different message hashes", async function () {
      const message1 = "First message";
      const message2 = "Second message";
      const hash1 = ethers.keccak256(ethers.toUtf8Bytes(message1));
      const hash2 = ethers.keccak256(ethers.toUtf8Bytes(message2));

      const messageBytes1 = ethers.getBytes(hash1);
      const messageBytes2 = ethers.getBytes(hash2);

      const signature1 = await signer.signMessage(messageBytes1);
      const signature2 = await signer.signMessage(messageBytes2);

      // Verify correct combinations
      expect(
        await signatureValidator.verify(signer.address, hash1, signature1)
      ).to.equal(true);
      expect(
        await signatureValidator.verify(signer.address, hash2, signature2)
      ).to.equal(true);

      // Verify incorrect combinations
      expect(
        await signatureValidator.verify(signer.address, hash1, signature2)
      ).to.equal(false);
      expect(
        await signatureValidator.verify(signer.address, hash2, signature1)
      ).to.equal(false);
    });
  });

  describe("Signature length validation", function () {
    it("should revert with IncorrectSignature for undersized signature (1 byte)", async function () {
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      const shortSignature = "0x01";

      await expect(
        signatureValidator.verify(signer.address, messageHash, shortSignature)
      ).to.be.revertedWithCustomError(signatureValidator, "IncorrectSignature");
    });

    it("should revert with IncorrectSignature for undersized signature (64 bytes)", async function () {
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      // Create a 64-byte signature (missing 1 byte)
      const shortSignature = "0x" + "a".repeat(128); // 64 bytes in hex

      await expect(
        signatureValidator.verify(signer.address, messageHash, shortSignature)
      ).to.be.revertedWithCustomError(signatureValidator, "IncorrectSignature");
    });

    it("should revert with IncorrectSignature for oversized signature (66 bytes)", async function () {
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      // Create a 66-byte signature (1 byte too long)
      const longSignature = "0x" + "a".repeat(132); // 66 bytes in hex

      await expect(
        signatureValidator.verify(signer.address, messageHash, longSignature)
      ).to.be.revertedWithCustomError(signatureValidator, "IncorrectSignature");
    });

    it("should revert with IncorrectSignature for empty signature", async function () {
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      const emptySignature = "0x";

      await expect(
        signatureValidator.verify(signer.address, messageHash, emptySignature)
      ).to.be.revertedWithCustomError(signatureValidator, "IncorrectSignature");
    });
  });

  describe("Zero Address Protection", function () {
    it("should revert with ZeroAddress error when addr parameter is address(0)", async function () {
      const signature = await signer.signMessage(testMessageHash);
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));

      await expect(
        signatureValidator.verify(ethers.ZeroAddress, messageHash, signature)
      ).to.be.revertedWithCustomError(signatureValidator, "ZeroAddress");
    });

    it("should prevent zero address bypass attack vector", async function () {
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      const signature = await signer.signMessage(testMessageHash);

      // Attempt to use zero address should always revert, regardless of signature
      await expect(
        signatureValidator.verify(ethers.ZeroAddress, messageHash, signature)
      ).to.be.revertedWithCustomError(signatureValidator, "ZeroAddress");
    });

    it("should prevent zero address bypass with empty signature", async function () {
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      const emptySignature = "0x";

      // Zero address check should happen before signature length check
      await expect(
        signatureValidator.verify(
          ethers.ZeroAddress,
          messageHash,
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

  describe("Edge Cases", function () {
    it("should handle very long signature data", async () => {
      const testMessage = "test message";
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));

      // Create an overly long signature (should revert due to strict length check)
      const messageBytes = ethers.getBytes(messageHash);
      const validSignature = await signer.signMessage(messageBytes);
      const longSignature = validSignature + "deadbeef"; // Add extra data

      await expect(
        signatureValidator.verify(signer.address, messageHash, longSignature)
      ).to.be.revertedWithCustomError(signatureValidator, "IncorrectSignature");
    });

    it("should handle short signature data gracefully", async () => {
      const testMessage = "test message";
      const messageHash = ethers.keccak256(ethers.toUtf8Bytes(testMessage));
      const shortSignature = "0x1234"; // Too short to be a valid signature

      // Should revert with IncorrectSignature due to strict length check
      await expect(
        signatureValidator.verify(signer.address, messageHash, shortSignature)
      ).to.be.revertedWithCustomError(signatureValidator, "IncorrectSignature");
    });
  });
});
