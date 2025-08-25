import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployCollateralManagementWithRoles } from "./fixtures";
import { expect } from "chai";
import { ethers } from "ethers";

describe("CollateralManagementContract addition functionality", () => {
  describe("addPegInCollateral function should", function () {
    it("only allow registered accounts to add collateral", async function () {
      const { collateralManagement, signers, adder } = await loadFixture(
        deployCollateralManagementWithRoles
      );
      const registeredAccount = signers[0];
      const notRegisteredAccount = signers[1];
      const oneRbtcTx = { value: ethers.parseEther("1") };

      await expect(
        collateralManagement
          .connect(adder)
          .addPegInCollateralTo(registeredAccount.address, oneRbtcTx)
      ).not.to.be.reverted;
      await expect(
        collateralManagement
          .connect(notRegisteredAccount)
          .addPegInCollateral(oneRbtcTx)
      ).to.be.revertedWithCustomError(
        collateralManagement,
        "ProviderNotRegistered"
      );
      // adder can only add collateral to other accounts unless they are registered
      await expect(
        collateralManagement.connect(adder).addPegInCollateral(oneRbtcTx)
      ).to.be.revertedWithCustomError(
        collateralManagement,
        "ProviderNotRegistered"
      );
      const tx = await collateralManagement
        .connect(registeredAccount)
        .addPegInCollateral(oneRbtcTx);
      await expect(tx)
        .to.emit(collateralManagement, "PegInCollateralAdded")
        .withArgs(registeredAccount.address, oneRbtcTx.value);
      await expect(
        collateralManagement.getPegInCollateral(registeredAccount.address)
      ).to.eventually.eq(oneRbtcTx.value * 2n);
    });
  });

  describe("addPegOutCollateral function should", function () {
    it("only allow registered accounts to add collateral", async function () {
      const { collateralManagement, signers, adder } = await loadFixture(
        deployCollateralManagementWithRoles
      );
      const registeredAccount = signers[2];
      const notRegisteredAccount = signers[3];
      const oneRbtcTx = { value: ethers.parseEther("1") };

      await expect(
        collateralManagement
          .connect(adder)
          .addPegOutCollateralTo(registeredAccount.address, oneRbtcTx)
      ).not.to.be.reverted;
      await expect(
        collateralManagement
          .connect(notRegisteredAccount)
          .addPegOutCollateral(oneRbtcTx)
      ).to.be.revertedWithCustomError(
        collateralManagement,
        "ProviderNotRegistered"
      );
      // adder can only add collateral to other accounts unless they are registered
      await expect(
        collateralManagement.connect(adder).addPegOutCollateral(oneRbtcTx)
      ).to.be.revertedWithCustomError(
        collateralManagement,
        "ProviderNotRegistered"
      );
      const tx = await collateralManagement
        .connect(registeredAccount)
        .addPegOutCollateral(oneRbtcTx);
      await expect(tx)
        .to.emit(collateralManagement, "PegOutCollateralAdded")
        .withArgs(registeredAccount.address, oneRbtcTx.value);
      await expect(
        collateralManagement.getPegOutCollateral(registeredAccount.address)
      ).to.eventually.eq(oneRbtcTx.value * 2n);
    });
  });

  describe("addPegInCollateralTo function should", function () {
    it("only adder to add collateral to other accounts", async function () {
      const { collateralManagement, signers, adder } = await loadFixture(
        deployCollateralManagementWithRoles
      );
      const registeredAccount = signers[0];
      const notRegisteredAccount = signers[1];
      const oneRbtcTx = { value: ethers.parseEther("1") };

      const tx = await collateralManagement
        .connect(adder)
        .addPegInCollateralTo(registeredAccount.address, oneRbtcTx);
      await expect(tx)
        .to.emit(collateralManagement, "PegInCollateralAdded")
        .withArgs(registeredAccount.address, oneRbtcTx.value);
      await expect(
        collateralManagement.getPegInCollateral(registeredAccount.address)
      ).to.eventually.eq(oneRbtcTx.value);
      await expect(
        collateralManagement
          .connect(notRegisteredAccount)
          .addPegInCollateralTo(registeredAccount.address, oneRbtcTx)
      ).to.be.revertedWithCustomError(
        collateralManagement,
        "AccessControlUnauthorizedAccount"
      );
      await expect(
        collateralManagement
          .connect(registeredAccount)
          .addPegInCollateralTo(registeredAccount.address, oneRbtcTx)
      ).to.be.revertedWithCustomError(
        collateralManagement,
        "AccessControlUnauthorizedAccount"
      );
    });
  });

  describe("addPegOutCollateralTo function should", function () {
    it("only adder to add collateral to other accounts", async function () {
      const { collateralManagement, signers, adder } = await loadFixture(
        deployCollateralManagementWithRoles
      );
      const registeredAccount = signers[0];
      const notRegisteredAccount = signers[1];
      const oneRbtcTx = { value: ethers.parseEther("1") };

      const tx = await collateralManagement
        .connect(adder)
        .addPegOutCollateralTo(registeredAccount.address, oneRbtcTx);
      await expect(tx)
        .to.emit(collateralManagement, "PegOutCollateralAdded")
        .withArgs(registeredAccount.address, oneRbtcTx.value);
      await expect(
        collateralManagement.getPegOutCollateral(registeredAccount.address)
      ).to.eventually.eq(oneRbtcTx.value);
      await expect(
        collateralManagement
          .connect(notRegisteredAccount)
          .addPegOutCollateralTo(registeredAccount.address, oneRbtcTx)
      ).to.be.revertedWithCustomError(
        collateralManagement,
        "AccessControlUnauthorizedAccount"
      );
      await expect(
        collateralManagement
          .connect(registeredAccount)
          .addPegOutCollateralTo(registeredAccount.address, oneRbtcTx)
      ).to.be.revertedWithCustomError(
        collateralManagement,
        "AccessControlUnauthorizedAccount"
      );
    });
  });
});
