import { BigNumberish, Provider } from "ethers";
import { LiquidityBridgeContractV2 } from "../../typechain-types";
import { expect } from "chai";

/**
 * Creates an assertion that checks the difference between the balance of an address
 * before and after the assertion is created. The current balance is determined when
 * **this function** is called. The expected difference is compared with the difference
 * of the balance that the address has in the moment the assertion is called minus the
 * balance the address had when the assertion was created.
 *
 * @param args.source The source of the balance information. Might be an LBC instance
 * or an RPC provider. So this function might be used to verify network balance or
 * protocol balance.
 *
 * @param args.address The address to check the balance.
 *
 * @param args.expectedDiff The expected difference between the balance when this function
 * is called (the assert function creation) and the balance when the assert function
 * is called.
 *
 * @param args.message The message to display when the assertion fails.
 *
 * @returns { Promise<() => Promise<void>> } The assertion function itself. When the assertion function
 * is called it will fetch the balance again and subtract from it the balance that was fetched when
 * **this** function was called. The result is compared with the `expectedDiff` parameter.
 */
export async function createBalanceDifferenceAssertion(args: {
  source: LiquidityBridgeContractV2 | Provider;
  address: string;
  expectedDiff: BigNumberish;
  message: string;
}): Promise<() => Promise<void>> {
  const { source, address, expectedDiff, message } = args;

  const balanceNow = await source.getBalance(address);
  return async function () {
    const balanceAfter = await source.getBalance(address);
    expect(balanceAfter - balanceNow).to.equal(expectedDiff, message);
  };
}

/**
 * Creates an assertion that checks the difference between the balance of an address
 * before and after the assertion is created. The current balance is determined when
 * **this function** is called. The difference of the balance that the address has
 * when the assertion is called minus the balance the address had when the
 * assertion was created is compared to the `balanceUpdate` parameter received by the
 * assert function.
 *
 * The difference between this function and {@link createBalanceDifferenceAssertion} is
 * that in {@link createBalanceDifferenceAssertion} the expected difference is passed when
 * the assertion is created, while in this function the expected difference is passed when
 * the assertion is called. You should use this function when you are not sure about the
 * expected difference because it depends on other factors.
 *
 * @param args.source The source of the balance information. Might be an LBC instance
 * or an RPC provider. So this function might be used to verify network balance or
 * protocol balance.
 *
 * @param args.address The address to check the balance.
 *
 * @param args.message The message to display when the assertion fails.
 *
 * @returns { Promise<(balanceUpdate: bigint) => void> } The assertion function itself. When the assertion
 * function is called it will fetch the balance again and subtract from it the balance that was fetched when
 * **this** function was called. The result is compared with the `balanceUpdate` parameter.
 */
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

/**
 * This function has the same purpose as {@link createBalanceDifferenceAssertion} but
 * it is used to check the collateral balance of a liquidity provider. The difference
 * between this function and {@link createBalanceDifferenceAssertion} is that this function
 * is used to compare protocol collateral, while the other function is used to compare network
 * or protocol balance of any address.
 *
 * @param args.lbc The LBC contract instance.
 *
 * @param args.address The address to check the collateral.
 *
 * @param args.expectedDiff The expected difference between the collateral when this function
 * is called (the assert function creation) and the collateral when the assert function
 * is called.
 *
 * @param args.message The message to display when the assertion fails.
 *
 * @param args.type The type of collateral to check. It can be "pegin" or "pegout".
 *
 * @returns { Promise<() => Promise<void>> } The assertion function itself. When the assertion function
 * is called it will fetch the collateral again and subtract from it the collateral that was fetched when
 * **this** function was called. The result is compared with the `expectedDiff` parameter.
 */
export async function createCollateralUpdateAssertion(args: {
  lbc: LiquidityBridgeContractV2;
  address: string;
  expectedDiff: BigNumberish;
  message: string;
  type: "pegin" | "pegout";
}): Promise<() => Promise<void>> {
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
