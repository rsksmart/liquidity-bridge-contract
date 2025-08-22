import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployPegInContractFixture } from "./fixtures";
import { expect } from "chai";
import {
  BRIDGE_ADDRESS,
  PEGIN_CONSTANTS,
  ZERO_ADDRESS,
} from "../utils/constants";
import { deployLibraries } from "../../scripts/deployment-utils/deploy-libraries";
import hre, { ethers, upgrades } from "hardhat";
import { Flyover__factory } from "../../typechain-types";
import { deployCollateralManagement } from "../collateral/fixtures";

describe("PegInContract configurations", () => {
  describe("receive function should", function () {
    it("reject payments from addresses that are not the bridge", async function () {
      const { contract, signers } = await loadFixture(
        deployPegInContractFixture
      );
      for (const signer of signers) {
        await expect(
          signer.sendTransaction({
            to: contract,
            value: ethers.parseEther("1"),
          })
        ).to.be.revertedWithCustomError(contract, "PaymentNotAllowed");
      }
    });
  });

  describe("initialize function should", function () {
    it("initialize properly", async function () {
      const { contract, owner } = await loadFixture(deployPegInContractFixture);
      await expect(contract.VERSION()).to.eventually.eq("1.0.0");
      await expect(contract.dustThreshold()).to.eventually.eq(
        PEGIN_CONSTANTS.TEST_DUST_THRESHOLD
      );
      await expect(contract.owner()).to.eventually.eq(owner.address);
      await expect(contract.getFeePercentage()).to.eventually.eq(0n);
      await expect(contract.getFeeCollector()).to.eventually.eq(ZERO_ADDRESS);
      await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
    });

    it("allow to initialize only once", async () => {
      const { contract, initializationParams } = await loadFixture(
        deployPegInContractFixture
      );
      await expect(
        contract.initialize(...initializationParams)
      ).to.be.revertedWithCustomError(contract, "InvalidInitialization");
    });

    it("revert if there is no code in CollateralManagement", async () => {
      const deployResult = await deployCollateralManagement();
      const libraries = await deployLibraries(
        hre.network.name,
        "Quotes",
        "BtcUtils",
        "SignatureValidator"
      );
      const PegInContract = await ethers.getContractFactory("PegInContract", {
        libraries: {
          Quotes: libraries.Quotes.address,
          BtcUtils: libraries.BtcUtils.address,
          SignatureValidator: libraries.SignatureValidator.address,
        },
      });
      await expect(
        upgrades.deployProxy(
          PegInContract,
          [
            deployResult.owner.address,
            BRIDGE_ADDRESS,
            PEGIN_CONSTANTS.TEST_DUST_THRESHOLD,
            PEGIN_CONSTANTS.TEST_MIN_PEGIN,
            deployResult.signers[2].address,
            false,
            0,
            ZERO_ADDRESS,
          ],
          {
            unsafeAllow: ["external-library-linking"],
          }
        )
      ).to.be.revertedWithCustomError(
        { interface: Flyover__factory.createInterface() },
        "NoContract"
      );
    });
  });
  describe("setDustThreshold function should", function () {
    it("only allow the owner to modify the dust threshold", async function () {
      const { contract, signers } = await loadFixture(
        deployPegInContractFixture
      );
      const notOwner = signers[0];
      await expect(
        contract.connect(notOwner).setDustThreshold(1n)
      ).to.be.revertedWithCustomError(contract, "OwnableUnauthorizedAccount");
    });

    it("modify the dust threshold properly", async function () {
      const { contract, owner } = await loadFixture(deployPegInContractFixture);
      const tx = contract.connect(owner).setDustThreshold(1n);
      await expect(tx)
        .to.emit(contract, "DustThresholdSet")
        .withArgs(PEGIN_CONSTANTS.TEST_DUST_THRESHOLD, 1n);
      await expect(contract.dustThreshold()).to.eventually.eq(1n);
    });
  });

  describe("setCollateralManagement function should", function () {
    it("only allow the owner to modify the collateralManagement address", async function () {
      const { contract, signers } = await loadFixture(
        deployPegInContractFixture
      );
      const notOwner = signers[0];
      const otherContract = await deployCollateralManagement().then((result) =>
        result.collateralManagement.getAddress()
      );
      await expect(
        contract.connect(notOwner).setCollateralManagement(otherContract)
      ).to.be.revertedWithCustomError(contract, "OwnableUnauthorizedAccount");
    });

    it("revert if address does not have code", async function () {
      const { contract, owner, signers } = await loadFixture(
        deployPegInContractFixture
      );
      const eoa = await signers[1].getAddress();
      await expect(
        contract.connect(owner).setCollateralManagement(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(contract, "NoContract");
      await expect(
        contract.connect(owner).setCollateralManagement(eoa)
      ).to.be.revertedWithCustomError(contract, "NoContract");
    });

    it("modify collateralManagement properly", async function () {
      const { contract, owner, initializationParams } = await loadFixture(
        deployPegInContractFixture
      );
      const otherContract = await deployCollateralManagement().then((result) =>
        result.collateralManagement.getAddress()
      );
      const tx = contract.connect(owner).setCollateralManagement(otherContract);
      expect(initializationParams[4]).to.not.eq(otherContract);
      await expect(tx)
        .to.emit(contract, "CollateralManagementSet")
        .withArgs(initializationParams[4], otherContract);
    });
  });
});
