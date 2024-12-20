import { ethers } from "hardhat";
import { LP_COLLATERAL } from "./utils/constants";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployLbcWithProvidersFixture } from "./utils/fixtures";
import {
  createBalanceDifferenceAssertion,
  createBalanceUpdateAssertion,
  createCollateralUpdateAssertion,
} from "./utils/asserts";
import * as hardhatHelpers from "@nomicfoundation/hardhat-network-helpers";

describe("LiquidityBridgeContractV2 resignation process should", () => {
  it("fail when liquidityProdvider try to withdraw collateral without resign postion as liquidity provider before", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const provider = fixtureResult.liquidityProviders[1];
    let lbc = fixtureResult.lbc;
    lbc = lbc.connect(provider.signer);

    await expect(lbc.withdrawCollateral()).to.be.revertedWith("LBC021");
    const resignBlocks = await lbc.getResignDelayBlocks();
    await lbc.resign();
    await hardhatHelpers.mine(resignBlocks);
    await expect(lbc.withdrawCollateral()).not.to.be.reverted;
  });

  it("fail when LP resigns two times", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const provider = fixtureResult.liquidityProviders[1];
    let lbc = fixtureResult.lbc;
    const resignBlocks = await lbc.getResignDelayBlocks();
    lbc = lbc.connect(provider.signer);
    await expect(lbc.resign()).not.to.be.reverted;
    await expect(lbc.resign()).to.be.revertedWith("LBC001");
    await hardhatHelpers.mine(resignBlocks);
    await expect(lbc.withdrawCollateral()).not.to.be.reverted;
  });

  it("should resign", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const provider = fixtureResult.liquidityProviders[0];
    let lbc = fixtureResult.lbc;
    lbc = lbc.connect(provider.signer);
    const lpBalance = ethers.parseEther("0.5");
    await lbc.deposit({ value: lpBalance });
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
        expectedDiff: lpBalance * -1n,
        message: "Incorrect LBC balance after withdraw",
      });

    const lpBalanceAfterWithdrawAssertion = await createBalanceUpdateAssertion({
      source: ethers.provider,
      address: provider.signer.address,
      message: "Incorrect LP balance after withdraw",
    });

    const lpProtocolBalanceAfterWithdrawAssertion =
      await createBalanceDifferenceAssertion({
        source: lbc,
        address: provider.signer.address,
        expectedDiff: lpBalance * -1n,
        message: "Incorrect LP balance in LBC after withdraw",
      });

    const peginCollateralAfterWithdrawAssertion =
      await createCollateralUpdateAssertion({
        lbc: lbc,
        address: provider.signer.address,
        expectedDiff: (LP_COLLATERAL / 2n) * -1n,
        message: "Incorrect pegin collateral after withdraw",
        type: "pegin",
      });

    const pegoutCollateralAfterWithdrawAssertion =
      await createCollateralUpdateAssertion({
        lbc: lbc,
        address: provider.signer.address,
        expectedDiff: (LP_COLLATERAL / 2n) * -1n,
        message: "Incorrect pegout collateral after withdraw",
        type: "pegout",
      });

    const resignTx = await lbc.resign();
    const resignReceipt = await resignTx.wait();

    await lbcBalanceAfterResignAssertion();

    const withdrawTx = await lbc.withdraw(lpBalance);
    const withdrawReceipt = await withdrawTx.wait();

    await expect(resignTx)
      .to.emit(lbc, "Resigned")
      .withArgs(provider.signer.address);
    await expect(withdrawTx)
      .to.emit(lbc, "Withdrawal")
      .withArgs(provider.signer.address, lpBalance);

    await lbcBalanceAfterWithdrawAssertion();
    await lpBalanceAfterWithdrawAssertion(
      lpBalance - withdrawReceipt!.fee - resignReceipt!.fee
    );
    await lpProtocolBalanceAfterWithdrawAssertion();

    const lpBalanceAfterCollateralWithdrawAssertion =
      await createBalanceUpdateAssertion({
        source: ethers.provider,
        address: provider.signer.address,
        message: "Incorrect LP balance after withdraw",
      });

    const lbcBalanceAfterCollateralWithdrawAssertion =
      await createBalanceDifferenceAssertion({
        source: ethers.provider,
        address: await lbc.getAddress(),
        expectedDiff: LP_COLLATERAL * -1n,
        message: "Incorrect LBC balance after collateral withdraw",
      });

    await hardhatHelpers.mine(resignBlocks);

    const withdrawCollateralTx = await lbc.withdrawCollateral();
    const withdrawCollateralReceipt = await withdrawCollateralTx.wait();

    await expect(withdrawCollateralTx)
      .to.emit(lbc, "WithdrawCollateral")
      .withArgs(provider.signer.address, LP_COLLATERAL);
    await lpBalanceAfterCollateralWithdrawAssertion(
      LP_COLLATERAL - withdrawCollateralReceipt!.fee
    );
    await peginCollateralAfterWithdrawAssertion();
    await pegoutCollateralAfterWithdrawAssertion();
    await lbcBalanceAfterCollateralWithdrawAssertion();
    await expect(
      lbc.getCollateral(provider.signer.address)
    ).to.eventually.be.eq(0);
    await expect(
      lbc.getPegoutCollateral(provider.signer.address)
    ).to.eventually.be.eq(0);
  });
});
