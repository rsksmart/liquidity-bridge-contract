#!/usr/bin/env ts-node

/**
 * Helper script to generate Bitcoin transactions for testing
 * This is called via FFI from Foundry tests
 *
 * Usage: ts-node generate-btc-tx.ts <quoteHash> <depositAddress> <weiAmount> <scriptType>
 * Output: Hex string (raw BTC transaction, without 0x prefix)
 *
 * @param quoteHash - The quote hash (32 bytes hex, with or without 0x prefix)
 * @param depositAddress - The deposit address (hex encoded, with or without 0x prefix)
 * @param weiAmount - The amount in WEI (decimal string)
 * @param scriptType - One of: p2pkh, p2sh, p2wpkh, p2wsh, p2tr
 */

import { hexlify } from "ethers";
import { toLeHex } from "../../test/utils/encoding";

type BtcAddressType = "p2pkh" | "p2sh" | "p2wpkh" | "p2wsh" | "p2tr";

const WEI_TO_SAT_CONVERSION = 10n ** 10n;
const weiToSat = (wei: bigint) =>
  wei % WEI_TO_SAT_CONVERSION === 0n
    ? wei / WEI_TO_SAT_CONVERSION
    : wei / WEI_TO_SAT_CONVERSION + 1n;

// Convert 5-bit words back to 8-bit bytes
function from5BitWords(words: Uint8Array): Uint8Array {
  const BECH32_WORD_SIZE = 5;
  const BYTE_SIZE = 8;

  let currentValue = 0;
  let bitCount = 0;
  const result: number[] = [];

  for (const word of words) {
    currentValue = (currentValue << BECH32_WORD_SIZE) | word;
    bitCount += BECH32_WORD_SIZE;

    while (bitCount >= BYTE_SIZE) {
      bitCount -= BYTE_SIZE;
      result.push((currentValue >> bitCount) & 0xff);
    }
  }

  return new Uint8Array(result);
}

function generateRawTx(
  quoteHash: string,
  depositAddress: string,
  weiAmount: bigint,
  scriptType: BtcAddressType
): string {
  // Clean up inputs - remove 0x prefix if present
  quoteHash = quoteHash.replace(/^0x/, "");
  depositAddress = depositAddress.replace(/^0x/, "");

  // Convert deposit address hex to Uint8Array
  const addressBytes = new Uint8Array(
    depositAddress.match(/.{2}/g)!.map((byte) => parseInt(byte, 16))
  );

  let outputScript: number[];

  // Declare variables outside switch to avoid lexical declaration in case blocks
  let wpkhHash: Uint8Array;
  let wshHash: Uint8Array;
  let trPubkey: Uint8Array;

  switch (scriptType) {
    case "p2pkh":
      // OP_DUP OP_HASH160 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG
      // Address format: version byte (1) + hash160 (20)
      outputScript = [
        0x76,
        0xa9,
        0x14,
        ...addressBytes.slice(1, 21),
        0x88,
        0xac,
      ];
      break;
    case "p2sh":
      // OP_HASH160 <20 bytes> OP_EQUAL
      // Address format: version byte (1) + hash160 (20)
      outputScript = [0xa9, 0x14, ...addressBytes.slice(1, 21), 0x87];
      break;
    case "p2wpkh":
      // OP_0 <20 bytes>
      // Address is in bech32 format: witness version + 5-bit words
      // Convert 5-bit words back to raw 20-byte hash
      wpkhHash = from5BitWords(addressBytes.slice(1));
      outputScript = [0x00, 0x14, ...wpkhHash];
      break;
    case "p2wsh":
      // OP_0 <32 bytes>
      // Address is in bech32 format: witness version + 5-bit words
      // Convert 5-bit words back to raw 32-byte hash
      wshHash = from5BitWords(addressBytes.slice(1));
      outputScript = [0x00, 0x20, ...wshHash];
      break;
    case "p2tr":
      // OP_1 <32 bytes>
      // Address is in bech32m format: witness version + 5-bit words
      // Convert 5-bit words back to raw 32-byte pubkey
      trPubkey = from5BitWords(addressBytes.slice(1));
      outputScript = [0x51, 0x20, ...trPubkey];
      break;
    default:
      throw new Error(`Invalid scriptType: ${String(scriptType)}`);
  }

  const outputScriptHex = hexlify(new Uint8Array(outputScript)).slice(2);
  const outputSize = (outputScriptHex.length / 2).toString(16).padStart(2, "0");

  // Convert amount to satoshis and format as little-endian hex
  const satAmount = weiToSat(weiAmount);
  const amountHex = toLeHex(satAmount).padEnd(16, "0");

  // Build the transaction
  const btcTx = [
    "01000000", // Version
    "01", // Input count
    // Input: previous tx hash + output index + script length + script + sequence
    "013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
    "00000000",
    "6a",
    "47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
    "ffffffff",
    "02", // Output count
    // Output 1: amount (8 bytes LE) + script length + script
    amountHex,
    outputSize,
    outputScriptHex,
    // Output 2: OP_RETURN with quote hash
    "0000000000000000", // 0 amount
    "22", // script length (34 bytes)
    "6a20", // OP_RETURN PUSH32
    quoteHash,
    "00000000", // Locktime
  ].join("");

  return btcTx;
}

// Main execution
if (require.main === module) {
  const args = process.argv.slice(2);

  if (args.length !== 4) {
    console.error(
      "Usage: ts-node generate-btc-tx.ts <quoteHash> <depositAddress> <weiAmount> <scriptType>"
    );
    console.error(
      "Example: ts-node generate-btc-tx.ts 0x123... 0xabc... 1000000000000000000 p2pkh"
    );
    process.exit(1);
  }

  try {
    const [quoteHash, depositAddress, weiAmountStr, scriptType] = args;

    // Validate scriptType
    const validTypes: BtcAddressType[] = [
      "p2pkh",
      "p2sh",
      "p2wpkh",
      "p2wsh",
      "p2tr",
    ];
    if (!validTypes.includes(scriptType as BtcAddressType)) {
      throw new Error(
        `Invalid script type. Must be one of: ${validTypes.join(", ")}`
      );
    }

    const weiAmount = BigInt(weiAmountStr);
    const rawTx = generateRawTx(
      quoteHash,
      depositAddress,
      weiAmount,
      scriptType as BtcAddressType
    );

    // Output without 0x prefix for Solidity
    console.log(rawTx);
  } catch (error: unknown) {
    const errorMessage =
      error instanceof Error ? error.message : "Unknown error";
    console.error(`Error generating BTC transaction: ${errorMessage}`);
    process.exit(1);
  }
}

export { generateRawTx };
