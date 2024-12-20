import { BigNumberish, Provider } from "ethers";
import { LiquidityBridgeContractV2 } from "../../typechain-types";
import { expect } from "chai";

export async function createBalanceDifferenceAssertion(args: {
  source: LiquidityBridgeContractV2 | Provider;
  address: string;
  expectedDiff: BigNumberish;
  message: string;
}): Promise<() => void> {
  const { source, address, expectedDiff, message } = args;

  const balanceNow = await source.getBalance(address);
  return async function () {
    const balanceAfter = await source.getBalance(address);
    expect(balanceAfter - balanceNow).to.equal(expectedDiff, message);
  };
}

export async function createBalanceUpdateAssertion(args: {
  source: LiquidityBridgeContractV2 | Provider;
  address: string;
  message: string;
}): Promise<(balanceUpdate: bigint) => void> {
  const { source, address, message } = args;
  const balanceNow = await source.getBalance(address);
  return async function (balanceUpdate: BigNumberish) {
    const balanceAfter = await source.getBalance(address);
    expect(balanceAfter - balanceNow).to.equal(balanceUpdate, message);
  };
}

export async function createCollateralUpdateAssertion(args: {
  lbc: LiquidityBridgeContractV2;
  address: string;
  expectedDiff: BigNumberish;
  message: string;
  type: "pegin" | "pegout";
}): Promise<() => void> {
  let balanceNow: bigint;
  const { lbc, address, expectedDiff, message, type } = args;

  if (type === "pegin") {
    balanceNow = await lbc.getCollateral(address);
  } else {
    balanceNow = await lbc.getPegoutCollateral(address);
  }
  return async function () {
    let balanceAfter: bigint;
    if (type === "pegin") {
      balanceAfter = await lbc.getCollateral(address);
    } else {
      balanceAfter = await lbc.getPegoutCollateral(address);
    }
    expect(balanceAfter - balanceNow).to.equal(expectedDiff, message);
  };
}
