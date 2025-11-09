#!/usr/bin/env node

/**
 * Helper script to fetch Bitcoin transaction data for registerPegIn
 * This is called via FFI from Foundry scripts
 *
 * Usage: node fetch-btc-tx-data.js <txid> <mainnet|testnet>
 * Output: JSON with rawTx, pmt, and height
 */

const mempoolJS = require('@mempool/mempool.js');
const bitcoin = require('bitcoinjs-lib');
const pmtBuilder = require('@rsksmart/pmt-builder');

async function fetchTxData(txId, isMainnet) {
  try {
    const {
      bitcoin: { blocks, transactions },
    } = mempoolJS({
      hostname: 'mempool.space',
      network: isMainnet ? 'mainnet' : 'testnet',
    });

    // Fetch full raw transaction
    const btcRawTxFull = await transactions.getTxHex({ txid: txId }).catch(() => {
      throw new Error(`Transaction not found: ${txId}`);
    });

    // Parse and remove witness data
    const tx = bitcoin.Transaction.fromHex(btcRawTxFull);
    tx.ins.forEach((input) => {
      input.witness = [];
    });
    const btcRawTx = tx.toHex();

    // Get transaction status to find block
    const txStatus = await transactions.getTxStatus({ txid: txId });

    if (!txStatus.confirmed || !txStatus.block_hash) {
      throw new Error(`Transaction not confirmed yet: ${txId}`);
    }

    // Get all transactions in the block to build PMT
    const blockTxs = await blocks.getBlockTxids({ hash: txStatus.block_hash });
    const pmt = pmtBuilder.buildPMT(blockTxs, txId);

    // Return as JSON
    const result = {
      rawTx: btcRawTx,
      pmt: pmt.hex,
      height: txStatus.block_height,
      blockHash: txStatus.block_hash,
      confirmed: txStatus.confirmed
    };

    console.log(JSON.stringify(result));
  } catch (error) {
    console.error(`Error fetching transaction data: ${error.message}`);
    process.exit(1);
  }
}

// Main execution
if (require.main === module) {
  const args = process.argv.slice(2);

  if (args.length !== 2) {
    console.error('Usage: node fetch-btc-tx-data.js <txid> <mainnet|testnet>');
    process.exit(1);
  }

  const [txId, network] = args;
  const isMainnet = network.toLowerCase() === 'mainnet';

  fetchTxData(txId, isMainnet).catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}

module.exports = { fetchTxData };
