import { Interface } from "ethers";

export const matchAnyNumber = (value: unknown) =>
  typeof value === "bigint" || typeof value === "number";

export const matchSelector =
  (iface: Interface, error: string) => (value: unknown) =>
    value === iface.getError(error)?.selector;
