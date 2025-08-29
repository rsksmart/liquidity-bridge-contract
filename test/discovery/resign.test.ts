import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import * as hardhatHelpers from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import { deployLbcWithProvidersFixture } from "../utils/fixtures";
import {
  createBalanceDifferenceAssertion,
  createBalanceUpdateAssertion,
  createCollateralUpdateAssertion,
} from "../utils/asserts";

describe("Discovery resign flow should", () => {
  it("emit Resigned and hide provider from listing", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders } = fixtureResult;
    let lbc = fixtureResult.lbc;

    const lp = liquidityProviders[0];
    lbc = lbc.connect(lp.signer);

    const resignTx = await lbc.resign();
    await expect(resignTx).to.emit(lbc, "Resigned").withArgs(lp.signer.address);

    // Resigned provider must not appear in discovery list
    const listed = await lbc.getProviders();
    expect(listed.some((p) => p.provider === lp.signer.address)).to.eq(false);
  });

  it("prevent non-registered account from resigning", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { accounts } = fixtureResult;
    const lbc = fixtureResult.lbc.connect(accounts[0]);
    await expect(lbc.resign()).to.be.revertedWith("LBC001");
  });

  it("prevent collateral withdrawal before delay and allow after", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders } = fixtureResult;
    let lbc = fixtureResult.lbc;
    const lp = liquidityProviders[1];
    lbc = lbc.connect(lp.signer);

    const resignBlocks = await lbc.getResignDelayBlocks();

    await expect(lbc.withdrawCollateral()).to.be.revertedWith("LBC021");
    await lbc.resign();
    await expect(lbc.withdrawCollateral()).to.be.revertedWith("LBC022");

    await hardhatHelpers.mine(resignBlocks);
    await expect(lbc.withdrawCollateral()).not.to.be.reverted;
  });

  it("prevent double resign", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders } = fixtureResult;
    let lbc = fixtureResult.lbc;
    const lp = liquidityProviders[2];
    lbc = lbc.connect(lp.signer);

    await expect(lbc.resign()).not.to.be.reverted;
    await expect(lbc.resign()).to.be.revertedWith("LBC023");
  });

  describe("happy path (v2 parity)", () => {
    const LP_BALANCE = ethers.parseEther("0.5");

    it("resign when LP is both pegin and pegout", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      let lbc = fixtureResult.lbc;
      const lp = fixtureResult.liquidityProviders[0];
      const collateral = lp.registerParams[4]!.value as bigint;

      lbc = lbc.connect(lp.signer);
      await lbc.deposit({ value: LP_BALANCE });
      const resignBlocks = await lbc.getResignDelayBlocks();

      const lbcBalanceAfterResignAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: 0,
          message: "Incorrect LBC balance after resign",
        });

      const lbcBalanceAfterWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: LP_BALANCE * -1n,
          message: "Incorrect LBC balance after withdraw",
        });

      const lpBalanceAfterWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: lp.signer.address,
          message: "Incorrect LP balance after withdraw",
        });

      const lpProtocolBalanceAfterWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: lbc,
          address: lp.signer.address,
          expectedDiff: LP_BALANCE * -1n,
          message: "Incorrect LP balance in LBC after withdraw",
        });

      const peginCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc,
          address: lp.signer.address,
          expectedDiff: (collateral / 2n) * -1n,
          message: "Incorrect pegin collateral after withdraw",
          type: "pegin",
        });

      const pegoutCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc,
          address: lp.signer.address,
          expectedDiff: (collateral / 2n) * -1n,
          message: "Incorrect pegout collateral after withdraw",
          type: "pegout",
        });

      const resignTx = await lbc.resign();
      const resignReceipt = await resignTx.wait();
      await lbcBalanceAfterResignAssertion();

      const withdrawTx = await lbc.withdraw(LP_BALANCE);
      const withdrawReceipt = await withdrawTx.wait();

      await expect(resignTx)
        .to.emit(lbc, "Resigned")
        .withArgs(lp.signer.address);
      await expect(withdrawTx)
        .to.emit(lbc, "Withdrawal")
        .withArgs(lp.signer.address, LP_BALANCE);

      await lbcBalanceAfterWithdrawAssertion();
      await lpBalanceAfterWithdrawAssertion(
        LP_BALANCE - withdrawReceipt!.fee - resignReceipt!.fee
      );
      await lpProtocolBalanceAfterWithdrawAssertion();

      const lpBalanceAfterCollateralWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: lp.signer.address,
          message: "Incorrect LP balance after collateral withdraw",
        });

      const lbcBalanceAfterCollateralWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: collateral * -1n,
          message: "Incorrect LBC balance after collateral withdraw",
        });

      await hardhatHelpers.mine(resignBlocks);
      const withdrawCollateralTx = await lbc.withdrawCollateral();
      const withdrawCollateralReceipt = await withdrawCollateralTx.wait();
      await expect(withdrawCollateralTx)
        .to.emit(lbc, "WithdrawCollateral")
        .withArgs(lp.signer.address, collateral);
      await lpBalanceAfterCollateralWithdrawAssertion(
        collateral - withdrawCollateralReceipt!.fee
      );
      await peginCollateralAfterWithdrawAssertion();
      await pegoutCollateralAfterWithdrawAssertion();
      await lbcBalanceAfterCollateralWithdrawAssertion();
      await expect(lbc.getCollateral(lp.signer.address)).to.eventually.eq(0);
      await expect(lbc.getPegoutCollateral(lp.signer.address)).to.eventually.eq(
        0
      );
    });

    it("resign when LP is pegin only", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      let lbc = fixtureResult.lbc;
      const lp = fixtureResult.liquidityProviders[1];
      const collateral = lp.registerParams[4]!.value as bigint;

      lbc = lbc.connect(lp.signer);
      await lbc.deposit({ value: LP_BALANCE });
      const resignBlocks = await lbc.getResignDelayBlocks();

      const lbcBalanceAfterResignAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: 0,
          message: "Incorrect LBC balance after resign",
        });

      const lbcBalanceAfterWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: LP_BALANCE * -1n,
          message: "Incorrect LBC balance after withdraw",
        });

      const lpBalanceAfterWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: lp.signer.address,
          message: "Incorrect LP balance after withdraw",
        });

      const lpProtocolBalanceAfterWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: lbc,
          address: lp.signer.address,
          expectedDiff: LP_BALANCE * -1n,
          message: "Incorrect LP balance in LBC after withdraw",
        });

      const peginCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc,
          address: lp.signer.address,
          expectedDiff: collateral * -1n,
          message: "Incorrect pegin collateral after withdraw",
          type: "pegin",
        });

      const pegoutCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc,
          address: lp.signer.address,
          expectedDiff: 0n,
          message: "Incorrect pegout collateral after withdraw",
          type: "pegout",
        });

      const resignTx = await lbc.resign();
      const resignReceipt = await resignTx.wait();
      await lbcBalanceAfterResignAssertion();

      const withdrawTx = await lbc.withdraw(LP_BALANCE);
      const withdrawReceipt = await withdrawTx.wait();

      await expect(resignTx)
        .to.emit(lbc, "Resigned")
        .withArgs(lp.signer.address);
      await expect(withdrawTx)
        .to.emit(lbc, "Withdrawal")
        .withArgs(lp.signer.address, LP_BALANCE);

      await lbcBalanceAfterWithdrawAssertion();
      await lpBalanceAfterWithdrawAssertion(
        LP_BALANCE - withdrawReceipt!.fee - resignReceipt!.fee
      );
      await lpProtocolBalanceAfterWithdrawAssertion();

      const lpBalanceAfterCollateralWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: lp.signer.address,
          message: "Incorrect LP balance after collateral withdraw",
        });

      const lbcBalanceAfterCollateralWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: collateral * -1n,
          message: "Incorrect LBC balance after collateral withdraw",
        });

      await hardhatHelpers.mine(resignBlocks);
      const withdrawCollateralTx = await lbc.withdrawCollateral();
      const withdrawCollateralReceipt = await withdrawCollateralTx.wait();
      await expect(withdrawCollateralTx)
        .to.emit(lbc, "WithdrawCollateral")
        .withArgs(lp.signer.address, collateral);
      await lpBalanceAfterCollateralWithdrawAssertion(
        collateral - withdrawCollateralReceipt!.fee
      );
      await peginCollateralAfterWithdrawAssertion();
      await pegoutCollateralAfterWithdrawAssertion();
      await lbcBalanceAfterCollateralWithdrawAssertion();
      await expect(lbc.getCollateral(lp.signer.address)).to.eventually.eq(0);
      await expect(lbc.getPegoutCollateral(lp.signer.address)).to.eventually.eq(
        0
      );
    });

    it("resign when LP is pegout only", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      let lbc = fixtureResult.lbc;
      const lp = fixtureResult.liquidityProviders[2];
      const collateral = lp.registerParams[4]!.value as bigint;

      lbc = lbc.connect(lp.signer);
      const resignBlocks = await lbc.getResignDelayBlocks();

      const lbcBalanceAfterResignAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: 0,
          message: "Incorrect LBC balance after resign",
        });

      const peginCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc,
          address: lp.signer.address,
          expectedDiff: 0n,
          message: "Incorrect pegin collateral after withdraw",
          type: "pegin",
        });

      const pegoutCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc,
          address: lp.signer.address,
          expectedDiff: collateral * -1n,
          message: "Incorrect pegout collateral after withdraw",
          type: "pegout",
        });

      const resignTx = await lbc.resign();
      await resignTx.wait();
      await lbcBalanceAfterResignAssertion();
      await expect(resignTx)
        .to.emit(lbc, "Resigned")
        .withArgs(lp.signer.address);

      const lpBalanceAfterCollateralWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: lp.signer.address,
          message: "Incorrect LP balance after collateral withdraw",
        });

      const lbcBalanceAfterCollateralWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: collateral * -1n,
          message: "Incorrect LBC balance after collateral withdraw",
        });

      await hardhatHelpers.mine(resignBlocks);
      const withdrawCollateralTx = await lbc.withdrawCollateral();
      const withdrawCollateralReceipt = await withdrawCollateralTx.wait();
      await expect(withdrawCollateralTx)
        .to.emit(lbc, "WithdrawCollateral")
        .withArgs(lp.signer.address, collateral);
      await lpBalanceAfterCollateralWithdrawAssertion(
        collateral - withdrawCollateralReceipt!.fee
      );
      await peginCollateralAfterWithdrawAssertion();
      await pegoutCollateralAfterWithdrawAssertion();
      await lbcBalanceAfterCollateralWithdrawAssertion();
      await expect(lbc.getCollateral(lp.signer.address)).to.eventually.eq(0);
      await expect(lbc.getPegoutCollateral(lp.signer.address)).to.eventually.eq(
        0
      );
    });
  });
});
