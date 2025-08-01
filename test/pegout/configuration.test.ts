import {
  BRIDGE_ADDRESS,
  PEGOUT_CONSTANTS,
  ZERO_ADDRESS,
} from "../utils/constants";
import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import {
  deployCollateralManagement,
  deployPegOutContractFixture,
} from "./fixtures";
import { deployLibraries } from "../../scripts/deployment-utils/deploy-libraries";
import hre, { ethers, upgrades } from "hardhat";
import { Flyover__factory } from "../../typechain-types";

describe("PegOutContract configurations", () => {
  describe("initialize function should", function () {
    it("initialize properly", async function () {
      const { contract, owner } = await loadFixture(
        deployPegOutContractFixture
      );
      await expect(contract.VERSION()).to.eventually.eq("1.0.0");
      await expect(contract.btcBlockTime()).to.eventually.eq(
        PEGOUT_CONSTANTS.TEST_BTC_BLOCK_TIME
      );
      await expect(contract.dustThreshold()).to.eventually.eq(
        PEGOUT_CONSTANTS.TEST_DUST_THRESHOLD
      );
      await expect(contract.owner()).to.eventually.eq(owner.address);
      await expect(contract.getFeePercentage()).to.eventually.eq(0n);
      await expect(contract.getFeeCollector()).to.eventually.eq(ZERO_ADDRESS);
      await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
    });

    it("allow to initialize only once", async () => {
      const { contract, initializationParams } = await loadFixture(
        deployPegOutContractFixture
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
      const PegOutContract = await ethers.getContractFactory("PegOutContract", {
        libraries: {
          Quotes: libraries.Quotes.address,
          BtcUtils: libraries.BtcUtils.address,
          SignatureValidator: libraries.SignatureValidator.address,
        },
      });
      await expect(
        upgrades.deployProxy(
          PegOutContract,
          [
            deployResult.owner.address,
            BRIDGE_ADDRESS,
            PEGOUT_CONSTANTS.TEST_DUST_THRESHOLD,
            deployResult.signers[2].address,
            false,
            PEGOUT_CONSTANTS.TEST_BTC_BLOCK_TIME,
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
        deployPegOutContractFixture
      );
      const notOwner = signers[0];
      await expect(
        contract.connect(notOwner).setDustThreshold(1n)
      ).to.be.revertedWithCustomError(contract, "OwnableUnauthorizedAccount");
    });

    it("modify the dust threshold properly", async function () {
      const { contract, owner } = await loadFixture(
        deployPegOutContractFixture
      );
      const tx = contract.connect(owner).setDustThreshold(1n);
      await expect(tx)
        .to.emit(contract, "DustThresholdSet")
        .withArgs(PEGOUT_CONSTANTS.TEST_DUST_THRESHOLD, 1n);
      await expect(contract.dustThreshold()).to.eventually.eq(1n);
    });
  });

  describe("setBtcBlockTime function should", function () {
    it("only allow the owner to modify the BTC block time", async function () {
      const { contract, signers } = await loadFixture(
        deployPegOutContractFixture
      );
      const notOwner = signers[0];
      await expect(
        contract.connect(notOwner).setBtcBlockTime(5n)
      ).to.be.revertedWithCustomError(contract, "OwnableUnauthorizedAccount");
    });

    it("modify the BTC block time properly", async function () {
      const { contract, owner } = await loadFixture(
        deployPegOutContractFixture
      );
      const tx = contract.connect(owner).setBtcBlockTime(5n);
      await expect(tx)
        .to.emit(contract, "BtcBlockTimeSet")
        .withArgs(PEGOUT_CONSTANTS.TEST_BTC_BLOCK_TIME, 5n);
      await expect(contract.btcBlockTime()).to.eventually.eq(5n);
    });
  });

  describe("setCollateralManagement function should", function () {
    it("only allow the owner to modify the collateralManagement address", async function () {
      const { contract, signers } = await loadFixture(
        deployPegOutContractFixture
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
        deployPegOutContractFixture
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
        deployPegOutContractFixture
      );
      const otherContract = await deployCollateralManagement().then((result) =>
        result.collateralManagement.getAddress()
      );
      const tx = contract.connect(owner).setCollateralManagement(otherContract);
      expect(initializationParams[3]).to.not.eq(otherContract);
      await expect(tx)
        .to.emit(contract, "CollateralManagementSet")
        .withArgs(initializationParams[3], otherContract);
    });
  });
});
