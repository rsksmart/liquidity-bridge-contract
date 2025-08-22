import { COLLATERAL_CONSTANTS } from "../utils/constants";
import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployCollateralManagement } from "./fixtures";

describe("CollateralManagementContract configurations", () => {
  describe("initialize function should", function () {
    it("initialize properly", async function () {
      const { collateralManagement, owner } = await loadFixture(
        deployCollateralManagement
      );
      await expect(collateralManagement.VERSION()).to.eventually.eq("1.0.0");
      await expect(collateralManagement.getMinCollateral()).to.eventually.eq(
        COLLATERAL_CONSTANTS.TEST_MIN_COLLATERAL
      );
      await expect(
        collateralManagement.getResignDelayInBlocks()
      ).to.eventually.eq(COLLATERAL_CONSTANTS.TEST_RESIGN_DELAY_BLOCKS);
      await expect(collateralManagement.getRewardPercentage()).to.eventually.eq(
        COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE
      );
      await expect(collateralManagement.owner()).to.eventually.eq(
        owner.address
      );
      await expect(collateralManagement.getPenalties()).to.eventually.eq(0n);
    });

    it("allow to initialize only once", async () => {
      const { collateralManagement, collateralManagementParams } =
        await loadFixture(deployCollateralManagement);
      await expect(
        collateralManagement.initialize(...collateralManagementParams)
      ).to.be.revertedWithCustomError(
        collateralManagement,
        "InvalidInitialization"
      );
    });
  });

  describe("setRewardPercentage function should", function () {
    it("only allow the owner to modify the reward percentage", async function () {
      const { collateralManagement, signers } = await loadFixture(
        deployCollateralManagement
      );
      const notOwner = signers[0];
      await expect(
        collateralManagement.connect(notOwner).setRewardPercentage(50n)
      )
        .to.be.revertedWithCustomError(
          collateralManagement,
          "AccessControlUnauthorizedAccount"
        )
        .withArgs(
          notOwner.address,
          await collateralManagement.DEFAULT_ADMIN_ROLE()
        );
    });

    it("modify the reward percentage properly", async function () {
      const { collateralManagement, owner } = await loadFixture(
        deployCollateralManagement
      );
      const tx = collateralManagement.connect(owner).setRewardPercentage(55n);
      await expect(tx)
        .to.emit(collateralManagement, "RewardPercentageSet")
        .withArgs(COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE, 55n);
      await expect(collateralManagement.getRewardPercentage()).to.eventually.eq(
        55n
      );
    });
  });

  describe("setResignDelayInBlocks function should", function () {
    it("only allow the owner to modify the resign delay in blocks", async function () {
      const { collateralManagement, signers } = await loadFixture(
        deployCollateralManagement
      );
      const notOwner = signers[0];
      await expect(
        collateralManagement.connect(notOwner).setResignDelayInBlocks(123n)
      )
        .to.be.revertedWithCustomError(
          collateralManagement,
          "AccessControlUnauthorizedAccount"
        )
        .withArgs(
          notOwner.address,
          await collateralManagement.DEFAULT_ADMIN_ROLE()
        );
    });

    it("modify the resign delay in blocks properly", async function () {
      const { collateralManagement, owner } = await loadFixture(
        deployCollateralManagement
      );
      const tx = collateralManagement
        .connect(owner)
        .setResignDelayInBlocks(321n);
      await expect(tx)
        .to.emit(collateralManagement, "ResignDelayInBlocksSet")
        .withArgs(COLLATERAL_CONSTANTS.TEST_RESIGN_DELAY_BLOCKS, 321n);
      await expect(
        collateralManagement.getResignDelayInBlocks()
      ).to.eventually.eq(321n);
    });
  });

  describe("setMinCollateral function should", function () {
    it("only allow the owner to modify the min collateral", async function () {
      const { collateralManagement, signers } = await loadFixture(
        deployCollateralManagement
      );
      const notOwner = signers[0];
      await expect(collateralManagement.connect(notOwner).setMinCollateral(1n))
        .to.be.revertedWithCustomError(
          collateralManagement,
          "AccessControlUnauthorizedAccount"
        )
        .withArgs(
          notOwner.address,
          await collateralManagement.DEFAULT_ADMIN_ROLE()
        );
    });

    it("modify the min collateral properly", async function () {
      const { collateralManagement, owner } = await loadFixture(
        deployCollateralManagement
      );
      const tx = collateralManagement.connect(owner).setMinCollateral(11n);
      await expect(tx)
        .to.emit(collateralManagement, "MinCollateralSet")
        .withArgs(COLLATERAL_CONSTANTS.TEST_MIN_COLLATERAL, 11n);
      await expect(collateralManagement.getMinCollateral()).to.eventually.eq(
        11n
      );
    });
  });
});
