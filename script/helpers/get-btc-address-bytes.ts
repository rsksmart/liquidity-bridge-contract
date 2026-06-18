#!/usr/bin/env ts-node

/**
 * Helper script to get Bitcoin address bytes in the format expected by the contract
 * For SegWit addresses, returns witness version + 5-bit words (bech32 format)
 * This is called via FFI from Foundry tests
 *
 * Usage: ts-node get-btc-address-bytes.ts <addressType>
 * Output: Hex string (address bytes in contract format, without 0x prefix)
 *
 * @param addressType - One of: p2pkh, p2sh, p2wpkh, p2wsh, p2tr
 */

import { bech32, bech32m } from "bech32";
import bs58check from "bs58check";

type BtcAddressType = "p2pkh" | "p2sh" | "p2wpkh" | "p2wsh" | "p2tr";

// Test addresses for each type (testnet)
const TEST_ADDRESSES = {
  p2pkh: "mxqk28jvEtvjxRN8k7W9hFEJfWz5VcUgHW", // Testnet P2PKH
  p2sh: "2N4DTeBWDF9yaF9TJVGcgcZDM7EQtsGwFjX", // Testnet P2SH
  p2wpkh: "tb1qlh84gv84mf7e28lsk3m75sgy7rx2lmvpr77rmw", // Testnet P2WPKH
  p2wsh: "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7", // Testnet P2WSH
  p2tr: "tb1ptt2hnzgzfhrfdyfz02l02wam6exd0mzuunfdgqg3ttt9yagp6daslx6grp", // Testnet P2TR
};

function getAddressBytes(addressType: BtcAddressType): string {
  const address = TEST_ADDRESSES[addressType];

  switch (addressType) {
    case "p2pkh":
    case "p2sh": {
      // Base58 addresses: decode and return full bytes (version + hash)
      const decoded = bs58check.decode(address);
      return Buffer.from(decoded).toString("hex");
    }
    case "p2wpkh": {
      // P2WPKH: witness version 0 + 5-bit words of 20-byte hash
      const decoded = bech32.decode(address);
      // decoded.words[0] is the witness version, skip it
      const witnessData = Buffer.from(bech32.fromWords(decoded.words.slice(1)));
      const result = Buffer.concat([Buffer.from([0x00]), witnessData]);
      return result.toString("hex");
    }
    case "p2wsh": {
      // P2WSH: witness version 0 + 5-bit words of 32-byte hash
      const decoded = bech32.decode(address);
      // decoded.words[0] is the witness version, skip it
      const witnessData = Buffer.from(bech32.fromWords(decoded.words.slice(1)));
      const result = Buffer.concat([Buffer.from([0x00]), witnessData]);
      return result.toString("hex");
    }
    case "p2tr": {
      // P2TR: witness version 1 + 5-bit words of 32-byte pubkey
      const decoded = bech32m.decode(address);
      // decoded.words[0] is the witness version, skip it
      const witnessData = Buffer.from(
        bech32m.fromWords(decoded.words.slice(1))
      );
      const result = Buffer.concat([Buffer.from([0x01]), witnessData]);
      return result.toString("hex");
    }
    default:
      throw new Error(`Invalid addressType: ${String(addressType)}`);
  }
}

// Main execution
if (require.main === module) {
  const args = process.argv.slice(2);

  if (args.length !== 1) {
    console.error("Usage: ts-node get-btc-address-bytes.ts <addressType>");
    console.error("addressType: p2pkh | p2sh | p2wpkh | p2wsh | p2tr");
    process.exit(1);
  }

  try {
    const addressType = args[0] as BtcAddressType;
    const validTypes: BtcAddressType[] = [
      "p2pkh",
      "p2sh",
      "p2wpkh",
      "p2wsh",
      "p2tr",
    ];

    if (!validTypes.includes(addressType)) {
      throw new Error(
        `Invalid address type. Must be one of: ${validTypes.join(", ")}`
      );
    }

    const addressBytes = getAddressBytes(addressType);
    console.log(addressBytes);
  } catch (error: unknown) {
    const errorMessage =
      error instanceof Error ? error.message : "Unknown error";
    console.error(`Error getting address bytes: ${errorMessage}`);
    process.exit(1);
  }
}

export { getAddressBytes };
