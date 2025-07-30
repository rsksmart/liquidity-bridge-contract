import hre, { upgrades, ethers } from "hardhat";
import { BRIDGE_ADDRESS, ZERO_ADDRESS } from "../utils/constants";
import { deployLibraries } from "../../scripts/deployment-utils/deploy-libraries";
import { expect } from "chai";
import { PegOutContract } from "../../typechain-types";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

// TODO this should be removed once the collateral management has its final implementation and test files, then
// this file should import a function from there
async function deployCollateralManagement() {
  const CollateralManagement = await ethers.getContractFactory(
    "CollateralManagementContract"
  );
  const owner = await ethers.getSigners().then((s) => s.at(0));
  const collateralManagement = await upgrades.deployProxy(
    CollateralManagement,
    [owner?.address, 500n, ethers.parseEther("0.6"), 500n],
    {
      unsafeAllow: ["external-library-linking"],
    }
  );
  return collateralManagement;
}

describe("PegOutContract configurations", () => {
  const TEST_DUST_THRESHOLD = 2300n * 65164000n;
  const TEST_BTC_BLOCK_TIME = 3600;

  async function deployFixture() {
    const signers = await ethers.getSigners();
    const lastSigner = signers.pop();
    if (!lastSigner) {
      throw new Error("owner can't be undefined");
    }
    const owner = lastSigner;
    const collateralManagement = await deployCollateralManagement().then(
      (contract) => contract.getAddress()
    );

    const initializationParams: Parameters<PegOutContract["initialize"]> = [
      owner.address,
      BRIDGE_ADDRESS,
      TEST_DUST_THRESHOLD,
      collateralManagement,
      false,
      TEST_BTC_BLOCK_TIME,
      0,
      ZERO_ADDRESS,
    ];

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

    const contract = await upgrades.deployProxy(
      PegOutContract,
      initializationParams,
      {
        unsafeAllow: ["external-library-linking"],
      }
    );
    return { contract, owner, signers, initializationParams };
  }

  describe("initialize function should", function () {
    it("initialize properly", async function () {
      const { contract, owner } = await loadFixture(deployFixture);
      await expect(contract.VERSION()).to.eventually.eq("1.0.0");
      await expect(contract.btcBlockTime()).to.eventually.eq(
        TEST_BTC_BLOCK_TIME
      );
      await expect(contract.dustThreshold()).to.eventually.eq(
        TEST_DUST_THRESHOLD
      );
      await expect(contract.owner()).to.eventually.eq(owner.address);
      await expect(contract.getFeePercentage()).to.eventually.eq(0n);
      await expect(contract.getFeeCollector()).to.eventually.eq(ZERO_ADDRESS);
      await expect(contract.getCurrentContribution()).to.eventually.eq(0n);
    });

    it("allow to initialize only once", async () => {
      const { contract, initializationParams } = await loadFixture(
        deployFixture
      );
      await expect(
        contract.initialize(...initializationParams)
      ).to.be.revertedWithCustomError(contract, "InvalidInitialization");
    });
  });

  describe("setDustThreshold function should", function () {
    it("only allow the owner to modify the dust threshold", async function () {
      const { contract, signers } = await loadFixture(deployFixture);
      const notOwner = signers[0];
      await expect(
        contract.connect(notOwner).setDustThreshold(1n)
      ).to.be.revertedWithCustomError(contract, "OwnableUnauthorizedAccount");
    });

    it("modify the dust threshold properly", async function () {
      const { contract, owner } = await loadFixture(deployFixture);
      const tx = contract.connect(owner).setDustThreshold(1n);
      await expect(tx)
        .to.emit(contract, "DustThresholdSet")
        .withArgs(TEST_DUST_THRESHOLD, 1n);
      await expect(contract.dustThreshold()).to.eventually.eq(1n);
    });
  });

  describe("setBtcBlockTime function should", function () {
    it("only allow the owner to modify the BTC block time", async function () {
      const { contract, signers } = await loadFixture(deployFixture);
      const notOwner = signers[0];
      await expect(
        contract.connect(notOwner).setBtcBlockTime(5n)
      ).to.be.revertedWithCustomError(contract, "OwnableUnauthorizedAccount");
    });

    it("modify the BTC block time properly", async function () {
      const { contract, owner } = await loadFixture(deployFixture);
      const tx = contract.connect(owner).setBtcBlockTime(5n);
      await expect(tx)
        .to.emit(contract, "BtcBlockTimeSet")
        .withArgs(TEST_BTC_BLOCK_TIME, 5n);
      await expect(contract.btcBlockTime()).to.eventually.eq(5n);
    });
  });

  describe("setCollateralManagement function should", function () {
    it("only allow the owner to modify the collateralManagement address", async function () {
      const { contract, signers } = await loadFixture(deployFixture);
      const notOwner = signers[0];
      const otherContract = await deployCollateralManagement().then((c) =>
        c.getAddress()
      );
      await expect(
        contract.connect(notOwner).setCollateralManagement(otherContract)
      ).to.be.revertedWithCustomError(contract, "OwnableUnauthorizedAccount");
    });

    it("revert if address does not have code", async function () {
      const { contract, owner, signers } = await loadFixture(deployFixture);
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
        deployFixture
      );
      const otherContract = await deployCollateralManagement().then((c) =>
        c.getAddress()
      );
      const tx = contract.connect(owner).setCollateralManagement(otherContract);
      expect(initializationParams[3]).to.not.eq(otherContract);
      await expect(tx)
        .to.emit(contract, "CollateralManagementSet")
        .withArgs(initializationParams[3], otherContract);
    });
  });
});
