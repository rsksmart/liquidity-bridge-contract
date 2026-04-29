import {
  BrowserProvider,
  BytesLike,
  ContractTransactionReceipt,
  getBytes,
  hexlify,
  parseEther,
  Wallet,
} from "ethers";
import {
  BtcCaller,
  formatHex,
  getBitcoinRpcCaller,
  INTEGRATION_TEST_TIMEOUT,
  IntegrationTestConfig,
  loadConfig,
  sendBtc,
  sleep,
  waitForBtcTransaction,
} from "./common";
import { LiquidityBridgeContractV2, QuotesV2 } from "../typechain-types";
import { parseBtcAddress } from "../tasks/utils/quote";
import hre, { ethers } from "hardhat";
import * as bs58check from "bs58check";
import { totalValue } from "../test/utils/quotes";
import { expect } from "chai";
import { weiToSat } from "../test/utils/btc";
import { buildPMT } from "@rsksmart/pmt-builder";

describe("Flyover pegout process should", function () {
  this.timeout(INTEGRATION_TEST_TIMEOUT);
  let config: IntegrationTestConfig;
  let interval: number;
  let lpAccount: Wallet;
  let userAccount: Wallet;
  let userBtcEncodedAddress: string;

  let lbc: LiquidityBridgeContractV2;
  let bitcoinRpc: BtcCaller;

  let quote: QuotesV2.PegOutQuoteStruct;
  let quoteHash: BytesLike;
  let signedQuote: BytesLike;

  before(async () => {
    const provider = new BrowserProvider(hre.network.provider);
    config = await loadConfig();
    interval = config.pollingIntervalInSeconds * 1000;
    lpAccount = new Wallet(config.lpPrivateKey, provider);
    userAccount = new Wallet(config.userPrivateKey, provider);
    userBtcEncodedAddress = config.userBtcAddress;

    const lpBtcAddress = bs58check.decode(config.lpBtcAddress);
    const userBtcAddress = parseBtcAddress(config.userBtcAddress);

    lbc = await ethers.getContractAt(
      "LiquidityBridgeContractV2",
      config.lbcAddress
    );
    bitcoinRpc = getBitcoinRpcCaller(config.btc);

    const timestamp = Math.floor(Date.now() / 1000);
    const transferTime = 1800,
      expireDate = 3600;
    const nonce = Math.floor(Math.random() * Number.MAX_SAFE_INTEGER);
    const height = await hre.ethers.provider
      .getBlock("latest")
      .then((block) => block!.number);

    const productFeePercentage = await lbc.productFeePercentage();
    const value = parseEther("0.6");
    const productFee = (BigInt(productFeePercentage) * value) / BigInt(100);
    const daoAddress = await lbc.daoFeeCollectorAddress();
    const daoGas = await provider.estimateGas({
      to: daoAddress,
      value: productFee.toString(),
    });
    const gasPrice = await provider
      .getFeeData()
      .then((result) => result.gasPrice!);
    const daoGasCost = gasPrice * daoGas;
    const btcNetworkFee = parseEther(config.btc.txFee.toString());

    quote = {
      lbcAddress: config.lbcAddress,
      lpRskAddress: lpAccount.address,
      btcRefundAddress: userBtcAddress,
      rskRefundAddress: userAccount.address,
      lpBtcAddress: lpBtcAddress,
      callFee: parseEther("0.0001"),
      penaltyFee: 1000000,
      nonce: nonce,
      deposityAddress: userBtcAddress,
      value: parseEther("0.6"),
      agreementTimestamp: timestamp,
      depositDateLimit: timestamp + transferTime,
      depositConfirmations: 1,
      transferConfirmations: 1,
      transferTime: transferTime,
      expireDate: timestamp + expireDate,
      expireBlock: height + 50,
      productFeeAmount: productFee,
      gasFee: daoGasCost + btcNetworkFee,
    };

    quoteHash = await lbc.hashPegoutQuote(quote).then((hash) => getBytes(hash));
    signedQuote = await lpAccount.signMessage(quoteHash);
  });

  it("execute depositPegout", async () => {
    lbc = lbc.connect(userAccount);
    const total = totalValue(quote);
    const receipt = await lbc
      .depositPegout(quote, signedQuote, { value: total })
      .then((tx) => tx.wait());
    const timestamp = await hre.ethers.provider
      .getBlock("latest")
      .then((block) => block!.timestamp);
    await expect(receipt)
      .to.emit(lbc, "PegOutDeposit")
      .withArgs(quoteHash, userAccount.address, total, timestamp);
  });

  it("execute refundPegOut", async () => {
    const amountInSatoshi = weiToSat(
      BigInt(quote.value) + BigInt(quote.callFee)
    );
    const amountInBtc = Number(amountInSatoshi) / 10 ** 8;
    if (config.btc.walletPassphrase) {
      await bitcoinRpc("walletpassphrase", {
        passphrase: config.btc.walletPassphrase,
        timeout: 60,
      });
    }
    const txHash = await sendBtc({
      rpc: bitcoinRpc,
      amountInBtc,
      toAddress: userBtcEncodedAddress,
      data: hexlify(quoteHash).slice(2),
    });
    const tx = await waitForBtcTransaction({
      rpc: bitcoinRpc,
      hash: txHash,
      confirmations: Number(quote.depositConfirmations),
      interval,
    });
    const block = await bitcoinRpc<{ tx: string[] }>("getblock", tx.blockhash);
    const txIndex = block.tx.findIndex((txId) => txId === txHash);
    const mb = buildMerkleBranch(block.tx, txHash, txIndex);

    let waitingForValidations = false;
    let receipt: ContractTransactionReceipt | null = null;
    lbc = lbc.connect(lpAccount);
    do {
      try {
        const refundEstimation = await lbc.refundPegOut.estimateGas(
          quoteHash,
          formatHex(tx.hex),
          formatHex(tx.blockhash),
          mb.path,
          mb.hashes.map((hash) => formatHex(hash))
        );
        const refundTx = await lbc.refundPegOut(
          quoteHash,
          formatHex(tx.hex),
          formatHex(tx.blockhash),
          mb.path,
          mb.hashes.map((hash) => formatHex(hash)),
          { gasLimit: refundEstimation }
        );
        receipt = await refundTx.wait();
        waitingForValidations = false;
      } catch (e: unknown) {
        waitingForValidations = (e as Error).message.includes("LBC049");
        if (!waitingForValidations) {
          throw e;
        }
        console.info("Waiting for bridge validations...");
        await sleep(interval);
      }
    } while (waitingForValidations);
    await expect(receipt).to.emit(lbc, "PegOutRefunded").withArgs(quoteHash);
  });
});

function buildMerkleBranch(
  transactions: string[],
  txHash: string,
  txIndex: number
) {
  const hashes = [];
  const pmt = buildPMT(transactions, txHash);

  let path = 0,
    pathIndex = 0,
    levelOffset = 0;
  let currentNodeOffset = txIndex;
  let targetOffset;
  for (
    let levelSize = transactions.length;
    levelSize > 1;
    levelSize = Math.floor((levelSize + 1) / 2)
  ) {
    if (currentNodeOffset % 2 == 0) {
      targetOffset = Math.min(currentNodeOffset + 1, levelSize - 1);
    } else {
      targetOffset = currentNodeOffset - 1;
      path = path + (1 << pathIndex);
    }
    hashes.push(pmt.hashes[levelOffset + targetOffset]);

    levelOffset += levelSize;
    currentNodeOffset = currentNodeOffset / 2;
    pathIndex++;
  }

  return { hashes, path };
}
