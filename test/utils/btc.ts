import { bech32, bech32m } from "bech32";
import * as bs58check from "bs58check";
import { BytesLike, hexlify } from "ethers";
import {
  LiquidityBridgeContractV2,
  PegOutContract,
  QuotesV2,
} from "../../typechain-types";
import { toLeHex } from "./encoding";
import { Quotes } from "../../typechain-types/contracts/libraries";

export type BtcAddressType = "p2pkh" | "p2sh" | "p2wpkh" | "p2wsh" | "p2tr";

const WEI_TO_SAT_CONVERSION = 10n ** 10n;
export const weiToSat = (wei: bigint) =>
  wei % WEI_TO_SAT_CONVERSION === 0n
    ? wei / WEI_TO_SAT_CONVERSION
    : wei / WEI_TO_SAT_CONVERSION + 1n;

export function getTestBtcAddress(addressType: BtcAddressType): BytesLike {
  switch (addressType) {
    case "p2pkh":
      return bs58check.decode("mxqk28jvEtvjxRN8k7W9hFEJfWz5VcUgHW");
    case "p2sh":
      return bs58check.decode("2N4DTeBWDF9yaF9TJVGcgcZDM7EQtsGwFjX");
    case "p2wpkh":
      return new Uint8Array(
        bech32.decode("tb1qlh84gv84mf7e28lsk3m75sgy7rx2lmvpr77rmw").words
      );
    case "p2wsh":
      return new Uint8Array(
        bech32.decode(
          "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7"
        ).words
      );
    case "p2tr":
      return new Uint8Array(
        bech32m.decode(
          "tb1ptt2hnzgzfhrfdyfz02l02wam6exd0mzuunfdgqg3ttt9yagp6daslx6grp"
        ).words
      );
    default:
      throw new Error("Invalid btcAddressType");
  }
}

/**
 * Generates a raw BTC transaction paying to the address specified in the given quote.
 * The transaction will have two outputs, one for the specified amount and one null data
 * script output for the quote hash.
 * @param lbc The LBC contract instance to hash the quote
 * @param quote The pegout quote
 * @param scriptType The type of the output script to generate
 * @returns { Promise<string> } The raw BTC transaction
 */
export async function generateRawTx(
  lbc: Partial<{
    hashPegoutQuote: LiquidityBridgeContractV2["hashPegoutQuote"];
    hashPegOutQuote: PegOutContract["hashPegOutQuote"];
  }>,
  quote: QuotesV2.PegOutQuoteStruct & Quotes.PegOutQuoteStruct,
  scriptType: BtcAddressType = "p2pkh"
) {
  let quoteHash: BytesLike;
  let addressBytes: Uint8Array;
  if (lbc.hashPegoutQuote) {
    quoteHash = await lbc.hashPegoutQuote(quote);
    addressBytes = quote.deposityAddress as Uint8Array;
  } else {
    quoteHash = (await lbc.hashPegOutQuote?.(quote)) ?? "0x";
    addressBytes = quote.depositAddress as Uint8Array;
  }
  let outputScript: number[];
  switch (scriptType) {
    case "p2pkh":
      outputScript = [0x76, 0xa9, 0x14, ...addressBytes.slice(1), 0x88, 0xac];
      break;
    case "p2sh":
      outputScript = [0xa9, 0x14, ...addressBytes.slice(1), 0x87];
      break;
    case "p2wpkh":
      outputScript = [0x00, 0x14, ...bech32.fromWords(addressBytes.slice(1))];
      break;
    case "p2wsh":
      outputScript = [0x00, 0x20, ...bech32.fromWords(addressBytes.slice(1))];
      break;
    case "p2tr":
      outputScript = [0x51, 0x20, ...bech32m.fromWords(addressBytes.slice(1))];
      break;
    default:
      throw new Error("Invalid scriptType");
  }
  const outputScriptFragment = hexlify(new Uint8Array(outputScript)).slice(2);
  const outputSize = (outputScriptFragment.length / 2).toString(16);
  const amount = toLeHex(weiToSat(BigInt(quote.value))).padEnd(16, "0");
  const btcTx = `0x0100000001013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40000000006a47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4ffffffff02${amount}${outputSize}${outputScriptFragment}0000000000000000226a20${quoteHash.slice(
    2
  )}00000000`;
  return btcTx;
}

/**
 * Use this function to get hardcoded values to use as merkle proofs in tests
 */
export function getTestMerkleProof() {
  const blockHeaderHash =
    "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326";
  const partialMerkleTree =
    "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb426";
  const merkleBranchHashes = [
    "0x02327049330a25d4d17e53e79f478cbb79c53a509679b1d8a1505c5697afb326",
  ];
  return {
    blockHeaderHash,
    partialMerkleTree,
    merkleBranchHashes,
  };
}
