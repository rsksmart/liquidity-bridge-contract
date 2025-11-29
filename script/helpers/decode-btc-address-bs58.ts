#!/usr/bin/env ts-node

/**
 * Helper script to decode Bitcoin addresses using bs58 (no checksum validation)
 * This is called via FFI from Foundry tests
 *
 * Usage: ts-node decode-btc-address-bs58.ts <address>
 * Output: Hex string (without 0x prefix) - full decoded bytes including checksum
 */

import bs58 from "bs58";

function decodeBtcAddressBs58(address: string): string {
  try {
    // This returns the full decoded bytes: version + hash + checksum (25 bytes for P2SH)
    // The validation function will use only the first 21 bytes (version + hash)
    const decoded = bs58.decode(address);
    return Buffer.from(decoded).toString("hex");
  } catch (error) {
    const errorMessage =
      error instanceof Error ? error.message : "Unknown error";
    console.error(`Error decoding address: ${errorMessage}`);
    process.exit(1);
  }
}

// Main execution
if (require.main === module) {
  const args = process.argv.slice(2);

  if (args.length !== 1) {
    console.error("Usage: ts-node decode-btc-address-bs58.ts <address>");
    process.exit(1);
  }

  const address = args[0];
  const hexBytes = decodeBtcAddressBs58(address);
  console.log(hexBytes);
}

export { decodeBtcAddressBs58 };
