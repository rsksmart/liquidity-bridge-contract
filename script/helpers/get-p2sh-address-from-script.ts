#!/usr/bin/env ts-node

/**
 * Helper script to calculate P2SH address from a redeem script
 * This is called via FFI from Foundry tests
 *
 * Usage: ts-node get-p2sh-address-from-script.ts <redeemScriptHex> <mainnet>
 * Output: Hex string (version byte + hash160 + checksum = 25 bytes, without 0x prefix)
 */

import * as bitcoin from "bitcoinjs-lib";
import bs58 from "bs58";

function getP2SHAddressFromScript(
  redeemScriptHex: string,
  isMainnet: boolean
): string {
  try {
    // Convert hex string to buffer
    const redeemScript = Buffer.from(redeemScriptHex, "hex");

    // Calculate hash160 of the redeem script
    const hash160 = bitcoin.crypto.hash160(redeemScript);

    // Create P2SH address using bitcoinjs-lib (this creates the full base58check address)
    const network = isMainnet
      ? bitcoin.networks.bitcoin
      : bitcoin.networks.testnet;
    const p2shAddress = bitcoin.payments.p2sh({
      hash: hash160,
      network: network,
    }).address;

    if (!p2shAddress) {
      throw new Error("Failed to generate P2SH address");
    }

    // This returns 25 bytes: version + hash160 + checksum
    const decoded = bs58.decode(p2shAddress);

    // Return as hex (without 0x prefix)
    return Buffer.from(decoded).toString("hex");
  } catch (error) {
    const errorMessage =
      error instanceof Error ? error.message : "Unknown error";
    console.error(`Error calculating P2SH address: ${errorMessage}`);
    process.exit(1);
  }
}

// Main execution
if (require.main === module) {
  const args = process.argv.slice(2);

  if (args.length !== 2) {
    console.error(
      "Usage: ts-node get-p2sh-address-from-script.ts <redeemScriptHex> <mainnet>"
    );
    console.error(
      "  redeemScriptHex: Hex string of the redeem script (without 0x prefix)"
    );
    console.error("  mainnet: 'true' for mainnet, 'false' for testnet");
    process.exit(1);
  }

  const redeemScriptHex = args[0];
  const isMainnet = args[1] === "true";
  const hexBytes = getP2SHAddressFromScript(redeemScriptHex, isMainnet);
  console.log(hexBytes);
}

export { getP2SHAddressFromScript };
