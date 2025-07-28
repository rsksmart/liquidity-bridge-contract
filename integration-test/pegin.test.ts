import {
  BrowserProvider,
  BytesLike,
  concat,
  ContractTransactionReceipt,
  formatEther,
  getBytes,
  hexlify,
  keccak256,
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
import * as bs58check from "bs58check";
import {
  IBridge,
  BtcUtils,
  LiquidityBridgeContractV2,
  QuotesV2,
} from "../typechain-types";
import hre, { ethers } from "hardhat";
import { expect } from "chai";
import bs58 from "bs58";
import { totalValue } from "../test/utils/quotes";
import { buildPMT } from "@rsksmart/pmt-builder";

describe("Flyover pegin process should", function () {
  this.timeout(INTEGRATION_TEST_TIMEOUT);
  let config: IntegrationTestConfig;
  let interval: number;
  let lpAccount: Wallet;

  let lbc: LiquidityBridgeContractV2;
  let btcUtils: BtcUtils;
  let bridge: IBridge;

  let bitcoinRpc: BtcCaller;

  let quote: QuotesV2.PeginQuoteStruct;
  let quoteHash: BytesLike;
  let signedQuote: BytesLike;

  before(async () => {
    const provider = new BrowserProvider(hre.network.provider);
    config = await loadConfig();
    interval = config.pollingIntervalInSeconds * 1000;
    lpAccount = new Wallet(config.lpPrivateKey, provider);
    const userAccount = new Wallet(config.userPrivateKey, provider);

    const lpBtcAddress = bs58check.decode(config.lpBtcAddress);
    const userBtcAddress = bs58check.decode(config.userBtcAddress);

    lbc = await ethers.getContractAt(
      "LiquidityBridgeContractV2",
      config.lbcAddress
    );
    btcUtils = await ethers.getContractAt("BtcUtils", config.btcUtilsAddress);
    bridge = await ethers.getContractAt(
      "IBridge",
      "0x0000000000000000000000000000000001000006"
    );
    bitcoinRpc = getBitcoinRpcCaller(config.btc);

    const timestamp = Math.floor(Date.now() / 1000);
    const transferTime = 1800;
    const gasLimit = await provider.estimateGas({
      to: userAccount.address,
      data: "0x",
    });
    const gasPrice = await provider
      .getFeeData()
      .then((result) => result.gasPrice!);
    const cfuGasCost = gasPrice * gasLimit;
    const fedAddress = await bridge
      .getFederationAddress()
      .then((fed) => bs58check.decode(fed).slice(1));
    const nonce = Math.floor(Math.random() * Number.MAX_SAFE_INTEGER);

    const productFeePercentage = await lbc.productFeePercentage();
    const value = parseEther("0.7");
    const productFee = (BigInt(productFeePercentage) * value) / BigInt(100);
    const daoAddress = await lbc.daoFeeCollectorAddress();
    const daoGas = await provider.estimateGas({
      to: daoAddress,
      value: productFee.toString(),
    });
    const daoGasCost = gasPrice * daoGas;

    quote = {
      fedBtcAddress: fedAddress,
      lbcAddress: config.lbcAddress,
      liquidityProviderRskAddress: lpAccount.address,
      btcRefundAddress: userBtcAddress,
      rskRefundAddress: userAccount.address,
      liquidityProviderBtcAddress: lpBtcAddress,
      callFee: parseEther("0.01"),
      penaltyFee: 1000000,
      contractAddress: userAccount.address,
      data: "0x",
      gasLimit: gasLimit,
      nonce: nonce,
      value: value,
      agreementTimestamp: timestamp,
      timeForDeposit: transferTime,
      callTime: transferTime * 2,
      depositConfirmations: 1,
      callOnRegister: false,
      productFeeAmount: productFee,
      gasFee: cfuGasCost + daoGasCost,
    };

    quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    signedQuote = await lpAccount.signMessage(quoteHash);
  });

  it("execute callForUser", async () => {
    const cfuExtraGas = 180000n;
    lbc = lbc.connect(lpAccount);
    const tx = await lbc.callForUser(quote, {
      gasLimit: BigInt(quote.gasLimit) + cfuExtraGas,
      value: totalValue(quote),
    });
    await expect(tx)
      .to.emit(lbc, "CallForUser")
      .withArgs(
        lpAccount.address,
        quote.contractAddress,
        quote.gasLimit,
        quote.value,
        quote.data,
        true,
        quoteHash
      );
  });

  it("execute registerPegIn", async () => {
    const derivationAddress = await getDervivationAddress({
      quote,
      quoteHash,
      btcUtils,
      bridge,
    });
    const total = totalValue(quote);
    const amountInBtc = formatEther(total);

    if (config.btc.walletPassphrase) {
      await bitcoinRpc("walletpassphrase", {
        passphrase: config.btc.walletPassphrase,
        timeout: 60,
      });
    }
    const txHash = await sendBtc({
      rpc: bitcoinRpc,
      amountInBtc,
      toAddress: derivationAddress,
    });
    const tx = await waitForBtcTransaction({
      rpc: bitcoinRpc,
      hash: txHash,
      confirmations: Number(quote.depositConfirmations),
      interval,
    });

    const block = await bitcoinRpc<{ tx: string[]; height: number }>(
      "getblock",
      tx.blockhash
    );
    const rawTx = await bitcoinRpc<string>("getrawtransaction", txHash);
    const pmt = buildPMT(block.tx, txHash);
    let receipt: ContractTransactionReceipt | null = null;
    let waitingForValidations = false;
    lbc = lbc.connect(lpAccount);
    do {
      try {
        const tx = await lbc.registerPegIn(
          quote,
          signedQuote,
          formatHex(rawTx),
          formatHex(pmt.hex),
          block.height
        );
        receipt = await tx.wait();
        waitingForValidations = false;
      } catch (e: unknown) {
        waitingForValidations = (e as Error).message.includes("LBC031");
        if (!waitingForValidations) {
          throw e;
        }
        console.info("Waiting for bridge validations...");
        await sleep(interval);
      }
    } while (waitingForValidations);

    await expect(receipt)
      .to.emit(lbc, "PegInRegistered")
      .withArgs(quoteHash, parseEther(amountInBtc));
  });
});

async function getDervivationAddress(ags: {
  quote: QuotesV2.PeginQuoteStruct;
  quoteHash: BytesLike;
  btcUtils: BtcUtils;
  bridge: IBridge;
}) {
  const { quote, quoteHash, btcUtils, bridge } = ags;
  const derivationAddress = keccak256(
    concat([
      quoteHash,
      quote.btcRefundAddress,
      quote.lbcAddress as BytesLike,
      quote.liquidityProviderBtcAddress,
    ])
  );
  const redeemScript = [...getBytes(derivationAddress)]; // to convert from UInt8Array to array
  redeemScript.unshift(0x20);
  redeemScript.push(0x75);
  const powpegRedeemScript = await bridge
    .getActivePowpegRedeemScript()
    .then((result) => getBytes(result));
  redeemScript.push(...powpegRedeemScript);

  const derivationAddressBytes = await btcUtils
    .getP2SHAddressFromScript(hexlify(new Uint8Array(redeemScript)), false)
    .then((result) => getBytes(result));
  return bs58.encode(derivationAddressBytes);
}
