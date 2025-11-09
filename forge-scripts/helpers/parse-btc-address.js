#!/usr/bin/env node

/**
 * Helper script to parse Bitcoin addresses and output hex bytes
 * This is called via FFI from Foundry scripts
 *
 * Usage: node parse-btc-address.js <address>
 * Output: Hex string (without 0x prefix)
 */

const bitcoin = require("bitcoinjs-lib");

function parseBtcAddress(address) {
  try {
    // Try to decode the address using bitcoinjs-lib
    // This handles all Bitcoin address types automatically
    let decoded;

    try {
      // Try decoding as base58 address (P2PKH, P2SH)
      decoded = bitcoin.address.fromBase58Check(address);
      // Return the full decoded buffer (includes version byte)
      const versionByte = Buffer.from([decoded.version]);
      const fullAddress = Buffer.concat([versionByte, decoded.hash]);
      return fullAddress.toString("hex");
    } catch (e1) {
      // Not a base58 address, try bech32
      try {
        decoded = bitcoin.address.fromBech32(address);
        // For bech32, return version + data
        const versionByte = Buffer.from([decoded.version]);
        const fullAddress = Buffer.concat([versionByte, decoded.data]);
        return fullAddress.toString("hex");
      } catch (e2) {
        throw new Error(
          `Invalid Bitcoin address: ${address}. Not valid base58 or bech32 format.`
        );
      }
    }
  } catch (error) {
    console.error(`Error parsing address: ${error.message}`);
    process.exit(1);
  }
}

// Main execution
if (require.main === module) {
  const args = process.argv.slice(2);

  if (args.length !== 1) {
    console.error("Usage: node parse-btc-address.js <address>");
    process.exit(1);
  }

  const address = args[0];
  const hexBytes = parseBtcAddress(address);
  console.log(hexBytes);
}

module.exports = { parseBtcAddress };
