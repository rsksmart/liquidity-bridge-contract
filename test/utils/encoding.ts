import * as ethers from "ethers";

export const toLeHex = (n: ethers.BigNumberish) =>
  ethers
    .toBeHex(n)
    .slice(2)
    .match(/.{1,2}/g)!
    .reverse()
    .join("");

export const fromLeHex: (hex: string) => bigint = (hex: string) =>
  hex.startsWith("0x")
    ? fromLeHex(hex.slice(2))
    : ethers.getBigInt(
        "0x" +
          hex
            .match(/.{1,2}/g)!
            .reverse()
            .join("")
      );

export const toBeHex = (n: ethers.BigNumberish) => ethers.toBeHex(n).slice(2);
