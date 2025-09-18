import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import * as hardhatHelpers from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import { deployDiscoveryWithProvidersFixture } from "./fixtures";
import {
  createBalanceDifferenceAssertion,
  createBalanceUpdateAssertion,
} from "../utils/asserts";

describe("Discovery resign flow should", () => {
  it("emit Resigned and hide provider from listing", async () => {
    const fixtureResult = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const { discovery, collateralManagement, fullLp } = fixtureResult;

    const resignTx = await collateralManagement.connect(fullLp).resign();
    await expect(resignTx)
      .to.emit(collateralManagement, "Resigned")
      .withArgs(fullLp.address);

    // Resigned provider must not appear in discovery list
    const listed = await discovery.getProviders();
    expect(listed.some((p) => p.providerAddress === fullLp.address)).to.eq(
      false
    );
  });

  it("prevent non-registered account from resigning", async () => {
    const fixtureResult = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const { collateralManagement, signers } = fixtureResult;
    const nonRegisteredAccount = signers[0];
    await expect(
      collateralManagement.connect(nonRegisteredAccount).resign()
    ).to.be.revertedWithCustomError(
      collateralManagement,
      "ProviderNotRegistered"
    );
  });

  it("prevent collateral withdrawal before delay and allow after", async () => {
    const fixtureResult = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const { collateralManagement, pegInLp } = fixtureResult;

    const resignBlocks = await collateralManagement.getResignDelayInBlocks();

    await expect(
      collateralManagement.connect(pegInLp).withdrawCollateral()
    ).to.be.revertedWithCustomError(collateralManagement, "NotResigned");
    await collateralManagement.connect(pegInLp).resign();
    await expect(
      collateralManagement.connect(pegInLp).withdrawCollateral()
    ).to.be.revertedWithCustomError(
      collateralManagement,
      "ResignationDelayNotMet"
    );

    await hardhatHelpers.mine(resignBlocks);
    await expect(collateralManagement.connect(pegInLp).withdrawCollateral()).not
      .to.be.reverted;
  });

  it("prevent double resign", async () => {
    const fixtureResult = await loadFixture(
      deployDiscoveryWithProvidersFixture
    );
    const { collateralManagement, pegOutLp } = fixtureResult;

    await expect(collateralManagement.connect(pegOutLp).resign()).not.to.be
      .reverted;
    await expect(
      collateralManagement.connect(pegOutLp).resign()
    ).to.be.revertedWithCustomError(collateralManagement, "AlreadyResigned");
  });

  describe("happy path (split contracts)", () => {
    it("resign when LP is both pegin and pegout", async () => {
      const fixtureResult = await loadFixture(
        deployDiscoveryWithProvidersFixture
      );
      const { collateralManagement, fullLp, MIN_COLLATERAL } = fixtureResult;
      const collateral = MIN_COLLATERAL * 2n; // Both provider registers with 2x min collateral

      const resignBlocks = await collateralManagement.getResignDelayInBlocks();

      const collateralBalanceAfterResignAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await collateralManagement.getAddress(),
          expectedDiff: 0,
          message: "Incorrect collateral management balance after resign",
        });

      const lpBalanceAfterCollateralWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: fullLp.address,
          message: "Incorrect LP balance after collateral withdraw",
        });

      const collateralBalanceAfterCollateralWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await collateralManagement.getAddress(),
          expectedDiff: collateral * -1n,
          message:
            "Incorrect collateral management balance after collateral withdraw",
        });

      const resignTx = await collateralManagement.connect(fullLp).resign();
      const resignReceipt = await resignTx.wait();
      await collateralBalanceAfterResignAssertion();

      await expect(resignTx)
        .to.emit(collateralManagement, "Resigned")
        .withArgs(fullLp.address);

      await hardhatHelpers.mine(resignBlocks);
      const withdrawCollateralTx = await collateralManagement
        .connect(fullLp)
        .withdrawCollateral();
      const withdrawCollateralReceipt = await withdrawCollateralTx.wait();
      await expect(withdrawCollateralTx)
        .to.emit(collateralManagement, "WithdrawCollateral")
        .withArgs(fullLp.address, collateral);
      await lpBalanceAfterCollateralWithdrawAssertion(
        collateral - withdrawCollateralReceipt!.fee - resignReceipt!.fee
      );
      await collateralBalanceAfterCollateralWithdrawAssertion();
      await expect(
        collateralManagement.getPegInCollateral(fullLp.address)
      ).to.eventually.eq(0);
      await expect(
        collateralManagement.getPegOutCollateral(fullLp.address)
      ).to.eventually.eq(0);
    });

    it("resign when LP is pegin only", async () => {
      const fixtureResult = await loadFixture(
        deployDiscoveryWithProvidersFixture
      );
      const { collateralManagement, pegInLp, MIN_COLLATERAL } = fixtureResult;
      const collateral = MIN_COLLATERAL;

      const resignBlocks = await collateralManagement.getResignDelayInBlocks();

      const collateralBalanceAfterResignAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await collateralManagement.getAddress(),
          expectedDiff: 0,
          message: "Incorrect collateral management balance after resign",
        });

      const lpBalanceAfterCollateralWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: pegInLp.address,
          message: "Incorrect LP balance after collateral withdraw",
        });

      const collateralBalanceAfterCollateralWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await collateralManagement.getAddress(),
          expectedDiff: collateral * -1n,
          message:
            "Incorrect collateral management balance after collateral withdraw",
        });

      const resignTx = await collateralManagement.connect(pegInLp).resign();
      const resignReceipt = await resignTx.wait();
      await collateralBalanceAfterResignAssertion();

      await expect(resignTx)
        .to.emit(collateralManagement, "Resigned")
        .withArgs(pegInLp.address);

      await hardhatHelpers.mine(resignBlocks);
      const withdrawCollateralTx = await collateralManagement
        .connect(pegInLp)
        .withdrawCollateral();
      const withdrawCollateralReceipt = await withdrawCollateralTx.wait();
      await expect(withdrawCollateralTx)
        .to.emit(collateralManagement, "WithdrawCollateral")
        .withArgs(pegInLp.address, collateral);
      await lpBalanceAfterCollateralWithdrawAssertion(
        collateral - withdrawCollateralReceipt!.fee - resignReceipt!.fee
      );
      await collateralBalanceAfterCollateralWithdrawAssertion();
      await expect(
        collateralManagement.getPegInCollateral(pegInLp.address)
      ).to.eventually.eq(0);
      await expect(
        collateralManagement.getPegOutCollateral(pegInLp.address)
      ).to.eventually.eq(0);
    });

    it("resign when LP is pegout only", async () => {
      const fixtureResult = await loadFixture(
        deployDiscoveryWithProvidersFixture
      );
      const { collateralManagement, pegOutLp, MIN_COLLATERAL } = fixtureResult;
      const collateral = MIN_COLLATERAL;

      const resignBlocks = await collateralManagement.getResignDelayInBlocks();

      const collateralBalanceAfterResignAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await collateralManagement.getAddress(),
          expectedDiff: 0,
          message: "Incorrect collateral management balance after resign",
        });

      const lpBalanceAfterCollateralWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: pegOutLp.address,
          message: "Incorrect LP balance after collateral withdraw",
        });

      const collateralBalanceAfterCollateralWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await collateralManagement.getAddress(),
          expectedDiff: collateral * -1n,
          message:
            "Incorrect collateral management balance after collateral withdraw",
        });

      const resignTx = await collateralManagement.connect(pegOutLp).resign();
      const resignReceipt = await resignTx.wait();
      await collateralBalanceAfterResignAssertion();
      await expect(resignTx)
        .to.emit(collateralManagement, "Resigned")
        .withArgs(pegOutLp.address);

      await hardhatHelpers.mine(resignBlocks);
      const withdrawCollateralTx = await collateralManagement
        .connect(pegOutLp)
        .withdrawCollateral();
      const withdrawCollateralReceipt = await withdrawCollateralTx.wait();
      await expect(withdrawCollateralTx)
        .to.emit(collateralManagement, "WithdrawCollateral")
        .withArgs(pegOutLp.address, collateral);
      await lpBalanceAfterCollateralWithdrawAssertion(
        collateral - withdrawCollateralReceipt!.fee - resignReceipt!.fee
      );
      await collateralBalanceAfterCollateralWithdrawAssertion();
      await expect(
        collateralManagement.getPegInCollateral(pegOutLp.address)
      ).to.eventually.eq(0);
      await expect(
        collateralManagement.getPegOutCollateral(pegOutLp.address)
      ).to.eventually.eq(0);
    });
  });
});
