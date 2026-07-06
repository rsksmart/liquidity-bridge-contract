// Step 04 — build the SPV proof (BIG-ENDIAN, as the bridge wants) and the PMT for resolve.
// Run with NODE_PATH pointing at flyover-sdk/node_modules (for @rsksmart/pmt-builder):
//   NODE_PATH=<repo>/flyover-sdk/node_modules node 04-build-proof.js <depositTxidBE> <coinbaseTxidBE> <blockHashBE>
const [depositTxid, coinbaseTxid, blockHash] = process.argv.slice(2);
if (!depositTxid || !coinbaseTxid || !blockHash) {
  console.error("usage: node 04-build-proof.js <depositTxidBE> <coinbaseTxidBE> <blockHashBE>");
  process.exit(1);
}
// Bridge getBtcTransactionConfirmations params (big-endian/display order, as bitcoin-cli prints):
// block has 2 leaves [coinbase(idx0), deposit(idx1)] -> sibling = coinbase, path bit = 1.
console.log("TXBE=0x" + depositTxid);
console.log("BHBE=0x" + blockHash);
console.log("BRANCH=[0x" + coinbaseTxid + "]");
console.log("PATH_BITS=1");

// PMT for resolvePegIn's registerFastBridgeBtcTransaction:
try {
  const { buildPMT } = require("@rsksmart/pmt-builder");
  const pmt = buildPMT([coinbaseTxid, depositTxid], depositTxid);
  const hex = pmt.hex || (pmt.toString ? pmt.toString("hex") : pmt);
  console.log("PMT=0x" + hex);
} catch (e) {
  console.log("PMT_BUILD_ERROR=" + e.message);
}
