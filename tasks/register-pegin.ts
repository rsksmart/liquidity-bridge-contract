import { task, types } from "hardhat/config";
import { DeploymentConfig, read } from "../scripts/deployment-utils/deploy";
import { ApiPeginQuote, parsePeginQuote } from "./utils/quote";
import { readFileSync } from "fs";
import mempoolJS from "@mempool/mempool.js";
import { BigNumberish } from "ethers";
import { Transaction } from "bitcoinjs-lib";
import pmtBuilder from "@rsksmart/pmt-builder";

task("register-pegin")
  .setDescription(
    "Register a PegIn bitcoin transaction within the Liquidity Bridge Contract"
  )
  .addParam(
    "file",
    "The file containing the PegIn quote to register",
    undefined,
    types.inputFile
  )
  .addParam(
    "signature",
    "The signature of the Liquidity Provider committing to pay for the quote",
    undefined,
    types.string
  )
  .addParam(
    "txid",
    "The transaction id of the Bitcoin transaction that pays for the specific PegIn",
    undefined,
    types.string
  )
  .setAction(async (args, hre) => {
    const { ethers, network } = hre;

    const typedArgs = args as { file: string; signature: string; txid: string };
    const txId: string = typedArgs.txid;
    const inputFile: string = typedArgs.file;
    const signature: string = "0x" + typedArgs.signature;

    const addresses: Partial<DeploymentConfig> = read();
    const networkDeployments: Partial<DeploymentConfig[string]> | undefined =
      addresses[network.name];
    const lbcAddress = networkDeployments?.LiquidityBridgeContract?.address;
    if (!lbcAddress) {
      throw new Error(
        "LiquidityBridgeContract proxy deployment info not found"
      );
    }
    const lbc = await ethers.getContractAt(
      "LiquidityBridgeContractV2",
      lbcAddress
    );

    const fileContent = readFileSync(inputFile);
    const quote = parsePeginQuote(
      JSON.parse(fileContent.toString()) as ApiPeginQuote
    );
    const { rawTx, pmt, height } = await getRegisterParams(
      txId,
      network.name === "rskMainnet"
    );

    const gasEstimation = await lbc.registerPegIn.estimateGas(
      quote,
      signature,
      rawTx,
      pmt,
      height
    );
    console.info("Gas estimation for registerPegIn:", gasEstimation);

    const result = await lbc.registerPegIn.staticCall(
      quote,
      signature,
      rawTx,
      pmt,
      height
    );
    console.info("Expected result:", result);

    const tx = await lbc.registerPegIn(quote, signature, rawTx, pmt, height);
    const receipt = await tx.wait();
    console.info(`Transaction hash: ${receipt!.hash}`);
    console.info("Transaction receipt: ");
    console.info(receipt);
  });

async function getRegisterParams(
  txId: string,
  mainnet: boolean
): Promise<{
  rawTx: string;
  pmt: string;
  height: BigNumberish;
}> {
  const {
    bitcoin: { blocks, transactions },
  } = mempoolJS({
    hostname: "mempool.space",
    network: mainnet ? "mainnet" : "testnet",
  });

  const btcRawTxFull = await transactions.getTxHex({ txid: txId }).catch(() => {
    throw new Error("Transaction not found");
  });
  const tx = Transaction.fromHex(btcRawTxFull);
  tx.ins.forEach((input) => {
    input.witness = [];
  });
  const btcRawTx = tx.toHex();

  const txStatus = await transactions.getTxStatus({ txid: txId });
  const blockTxs = await blocks.getBlockTxids({ hash: txStatus.block_hash });
  const pmt = pmtBuilder.buildPMT(blockTxs, txId);

  return {
    rawTx: "0x" + btcRawTx,
    pmt: "0x" + pmt.hex,
    height: txStatus.block_height,
  };
}
