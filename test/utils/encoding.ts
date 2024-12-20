import * as ethers from "ethers";

/**
 * Converts number to little-endian hex without the 0x prefix
 * @param n The number to convert
 * @returns { string } The little-endian hex representation of the number
 */
export const toLeHex = (n: ethers.BigNumberish) =>
  ethers
    .toBeHex(n)
    .slice(2)
    .match(/.{1,2}/g)!
    .reverse()
    .join("");

/**
 * Converts a little-endian hex string to a number
 * @param hex The little-endian hex string
 * @returns { bigint } The number represented by the hex string
 */
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

/**
 * Converts a number to a big-endian hex string without the 0x prefix
 * @param n The number to convert
 * @returns { string } The big-endian hex representation of the number
 */
export const toBeHex = (n: ethers.BigNumberish) => ethers.toBeHex(n).slice(2);
