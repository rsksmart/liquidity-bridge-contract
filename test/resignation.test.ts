import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployLbcWithProvidersFixture } from "./utils/fixtures";
import {
  createBalanceDifferenceAssertion,
  createBalanceUpdateAssertion,
  createCollateralUpdateAssertion,
} from "./utils/asserts";
import * as hardhatHelpers from "@nomicfoundation/hardhat-network-helpers";
import { LiquidityBridgeContractV2 } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("LiquidityBridgeContractV2 resignation process should", () => {
  let lbc: LiquidityBridgeContractV2;
  let liquidityProvider: {
    signer: HardhatEthersSigner;
    registerParams: Parameters<LiquidityBridgeContractV2["register"]>;
  };
  let fixtureResult: Awaited<ReturnType<typeof deployLbcWithProvidersFixture>>;

  describe("happy path", () => {
    const LP_BALANCE = ethers.parseEther("0.5");

    beforeEach(async () => {
      fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      lbc = fixtureResult.lbc;
    });

    it("resign when LP is both pegin and pegout", async () => {
      liquidityProvider = fixtureResult.liquidityProviders[0];
      const collateral = fixtureResult.liquidityProviders[0].registerParams[4]!
        .value as bigint;
      lbc = lbc.connect(liquidityProvider.signer);
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
          address: liquidityProvider.signer.address,
          message: "Incorrect LP balance after withdraw",
        });

      const lpProtocolBalanceAfterWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: lbc,
          address: liquidityProvider.signer.address,
          expectedDiff: LP_BALANCE * -1n,
          message: "Incorrect LP balance in LBC after withdraw",
        });

      const peginCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc: lbc,
          address: liquidityProvider.signer.address,
          expectedDiff: (collateral / 2n) * -1n,
          message: "Incorrect pegin collateral after withdraw",
          type: "pegin",
        });

      const pegoutCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc: lbc,
          address: liquidityProvider.signer.address,
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
        .withArgs(liquidityProvider.signer.address);
      await expect(withdrawTx)
        .to.emit(lbc, "Withdrawal")
        .withArgs(liquidityProvider.signer.address, LP_BALANCE);

      await lbcBalanceAfterWithdrawAssertion();
      await lpBalanceAfterWithdrawAssertion(
        LP_BALANCE - withdrawReceipt!.fee - resignReceipt!.fee
      );
      await lpProtocolBalanceAfterWithdrawAssertion();

      const lpBalanceAfterCollateralWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: liquidityProvider.signer.address,
          message: "Incorrect LP balance after withdraw",
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
        .withArgs(liquidityProvider.signer.address, collateral);
      await lpBalanceAfterCollateralWithdrawAssertion(
        collateral - withdrawCollateralReceipt!.fee
      );
      await peginCollateralAfterWithdrawAssertion();
      await pegoutCollateralAfterWithdrawAssertion();
      await lbcBalanceAfterCollateralWithdrawAssertion();
      await expect(
        lbc.getCollateral(liquidityProvider.signer.address)
      ).to.eventually.be.eq(0);
      await expect(
        lbc.getPegoutCollateral(liquidityProvider.signer.address)
      ).to.eventually.be.eq(0);
    });

    it("resign when LP is pegin only", async () => {
      liquidityProvider = fixtureResult.liquidityProviders[1];
      const collateral = fixtureResult.liquidityProviders[1].registerParams[4]!
        .value as bigint;
      lbc = lbc.connect(liquidityProvider.signer);
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
          address: liquidityProvider.signer.address,
          message: "Incorrect LP balance after withdraw",
        });

      const lpProtocolBalanceAfterWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: lbc,
          address: liquidityProvider.signer.address,
          expectedDiff: LP_BALANCE * -1n,
          message: "Incorrect LP balance in LBC after withdraw",
        });

      const peginCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc: lbc,
          address: liquidityProvider.signer.address,
          expectedDiff: collateral * -1n,
          message: "Incorrect pegin collateral after withdraw",
          type: "pegin",
        });

      const pegoutCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc: lbc,
          address: liquidityProvider.signer.address,
          expectedDiff: 0n, // Pegin-only LP has no pegout collateral
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
        .withArgs(liquidityProvider.signer.address);
      await expect(withdrawTx)
        .to.emit(lbc, "Withdrawal")
        .withArgs(liquidityProvider.signer.address, LP_BALANCE);

      await lbcBalanceAfterWithdrawAssertion();
      await lpBalanceAfterWithdrawAssertion(
        LP_BALANCE - withdrawReceipt!.fee - resignReceipt!.fee
      );
      await lpProtocolBalanceAfterWithdrawAssertion();

      const lpBalanceAfterCollateralWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: liquidityProvider.signer.address,
          message: "Incorrect LP balance after withdraw",
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
        .withArgs(liquidityProvider.signer.address, collateral);
      await lpBalanceAfterCollateralWithdrawAssertion(
        collateral - withdrawCollateralReceipt!.fee
      );
      await peginCollateralAfterWithdrawAssertion();
      await pegoutCollateralAfterWithdrawAssertion();
      await lbcBalanceAfterCollateralWithdrawAssertion();
      await expect(
        lbc.getCollateral(liquidityProvider.signer.address)
      ).to.eventually.be.eq(0);
      await expect(
        lbc.getPegoutCollateral(liquidityProvider.signer.address)
      ).to.eventually.be.eq(0);
    });

    it("resign when LP is pegout only", async () => {
      liquidityProvider = fixtureResult.liquidityProviders[2];
      const collateral = fixtureResult.liquidityProviders[2].registerParams[4]!
        .value as bigint;
      lbc = lbc.connect(liquidityProvider.signer);

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
          lbc: lbc,
          address: liquidityProvider.signer.address,
          expectedDiff: 0n, // Pegout-only LP has no pegin collateral
          message: "Incorrect pegin collateral after withdraw",
          type: "pegin",
        });

      const pegoutCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc: lbc,
          address: liquidityProvider.signer.address,
          expectedDiff: collateral * -1n,
          message: "Incorrect pegout collateral after withdraw",
          type: "pegout",
        });

      const resignTx = await lbc.resign();
      await resignTx.wait();

      await lbcBalanceAfterResignAssertion();

      await expect(resignTx)
        .to.emit(lbc, "Resigned")
        .withArgs(liquidityProvider.signer.address);

      const lpBalanceAfterCollateralWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: liquidityProvider.signer.address,
          message: "Incorrect LP balance after withdraw",
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
        .withArgs(liquidityProvider.signer.address, collateral);
      await lpBalanceAfterCollateralWithdrawAssertion(
        collateral - withdrawCollateralReceipt!.fee
      );
      await peginCollateralAfterWithdrawAssertion();
      await pegoutCollateralAfterWithdrawAssertion();
      await lbcBalanceAfterCollateralWithdrawAssertion();
      await expect(
        lbc.getCollateral(liquidityProvider.signer.address)
      ).to.eventually.be.eq(0);
      await expect(
        lbc.getPegoutCollateral(liquidityProvider.signer.address)
      ).to.eventually.be.eq(0);
    });
  });

  describe("error cases", () => {
    beforeEach(async () => {
      fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      liquidityProvider = fixtureResult.liquidityProviders[0];
      lbc = fixtureResult.lbc;
      lbc = lbc.connect(liquidityProvider.signer);
    });

    it("fail when liquidityProdvider try to withdraw collateral without resign postion as liquidity provider before", async () => {
      await expect(lbc.withdrawCollateral()).to.be.revertedWith("LBC021");
      const resignBlocks = await lbc.getResignDelayBlocks();
      await lbc.resign();
      await hardhatHelpers.mine(resignBlocks);
      await expect(lbc.withdrawCollateral()).not.to.be.reverted;
    });

    it("fail when LP resigns two times", async () => {
      const resignBlocks = await lbc.getResignDelayBlocks();
      await expect(lbc.resign()).not.to.be.reverted;
      await expect(lbc.resign()).to.be.revertedWith("LBC023");
      await hardhatHelpers.mine(resignBlocks);
      await expect(lbc.withdrawCollateral()).not.to.be.reverted;
    });

    it("fail when LP is not registered", async () => {
      const signers = await ethers.getSigners();
      const lp = lbc.connect(signers[3]); // not registered LP
      await expect(lp.resign()).to.be.revertedWith("LBC001");
    });
  });
});
