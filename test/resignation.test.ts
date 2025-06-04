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
import { LiquidityBridgeContractV2 } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("LiquidityBridgeContractV2 resignation process should", () => {
  let lbc: LiquidityBridgeContractV2;
  let liquidityProvider: {
    signer: HardhatEthersSigner;
    registerParams: Parameters<LiquidityBridgeContractV2["register"]>;
  };
  let fixtureResult: Awaited<ReturnType<typeof deployLbcWithProvidersFixture>>;

  beforeEach(async () => {
    fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    liquidityProvider = fixtureResult.liquidityProviders[0];
    lbc = fixtureResult.lbc;
    lbc = lbc.connect(liquidityProvider.signer);
  });

  it("resign", async () => {
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
      address: liquidityProvider.signer.address,
      message: "Incorrect LP balance after withdraw",
    });

    const lpProtocolBalanceAfterWithdrawAssertion =
      await createBalanceDifferenceAssertion({
        source: lbc,
        address: liquidityProvider.signer.address,
        expectedDiff: lpBalance * -1n,
        message: "Incorrect LP balance in LBC after withdraw",
      });

    const peginCollateralAfterWithdrawAssertion =
      await createCollateralUpdateAssertion({
        lbc: lbc,
        address: liquidityProvider.signer.address,
        expectedDiff: (LP_COLLATERAL / 2n) * -1n,
        message: "Incorrect pegin collateral after withdraw",
        type: "pegin",
      });

    const pegoutCollateralAfterWithdrawAssertion =
      await createCollateralUpdateAssertion({
        lbc: lbc,
        address: liquidityProvider.signer.address,
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
      .withArgs(liquidityProvider.signer.address);
    await expect(withdrawTx)
      .to.emit(lbc, "Withdrawal")
      .withArgs(liquidityProvider.signer.address, lpBalance);

    await lbcBalanceAfterWithdrawAssertion();
    await lpBalanceAfterWithdrawAssertion(
      lpBalance - withdrawReceipt!.fee - resignReceipt!.fee
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
        expectedDiff: LP_COLLATERAL * -1n,
        message: "Incorrect LBC balance after collateral withdraw",
      });

    await hardhatHelpers.mine(resignBlocks);

    const withdrawCollateralTx = await lbc.withdrawCollateral();
    const withdrawCollateralReceipt = await withdrawCollateralTx.wait();

    await expect(withdrawCollateralTx)
      .to.emit(lbc, "WithdrawCollateral")
      .withArgs(liquidityProvider.signer.address, LP_COLLATERAL);
    await lpBalanceAfterCollateralWithdrawAssertion(
      LP_COLLATERAL - withdrawCollateralReceipt!.fee
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

  it("resign as pegout only, pegin only and both", async () => {
    // Both LP
    const peginAndPegoutLp = fixtureResult.liquidityProviders[0];
    lbc = lbc.connect(peginAndPegoutLp.signer);
    await expect(lbc.resign()).not.to.be.reverted;

    // Pegin only LP
    const peginOnlyLp = fixtureResult.liquidityProviders[1];
    lbc = lbc.connect(peginOnlyLp.signer);
    await expect(lbc.resign()).not.to.be.reverted;

    // Pegout only LP
    const pegoutOnlyLp = fixtureResult.liquidityProviders[2];
    lbc = lbc.connect(pegoutOnlyLp.signer);
    await expect(lbc.resign()).not.to.be.reverted;
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
