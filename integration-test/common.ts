import { BytesLike } from "ethers";
import { readFile } from "fs/promises";

export interface IntegrationTestConfig {
  pollingIntervalInSeconds: number;
  lbcAddress: string;
  btcUtilsAddress: string;
  lpPrivateKey: string;
  lpBtcAddress: string;
  userPrivateKey: string;
  userBtcAddress: string;
  btc: {
    url: string;
    user: string;
    pass: string;
    walletName: string;
    walletPassphrase: string;
    txFee: number;
  };
}

export const INTEGRATION_TEST_TIMEOUT = 1000 * 60 * 60 * 3; // 3 hours
export type BtcCaller = <T>(method: string, ...args: unknown[]) => Promise<T>;

export const sleep: (ms: number) => Promise<void> = (ms) =>
  new Promise((resolve) => setTimeout(resolve, ms));
export const formatHex = (hex: string) =>
  hex.startsWith("0x") ? hex : "0x" + hex;

export async function loadConfig(): Promise<IntegrationTestConfig> {
  const buffer = await readFile("integration-test/test.config.json");
  return JSON.parse(buffer.toString()) as IntegrationTestConfig;
}

export function getBitcoinRpcCaller(
  args: IntegrationTestConfig["btc"],
  debug = false
): BtcCaller {
  const { url, user, pass, walletName } = args;
  const headers = new Headers();
  headers.append("content-type", "application/json");
  const token = Buffer.from(`${user}:${pass}`).toString("base64");
  headers.append("Authorization", "Basic " + token);

  return async function <T>(method: string, ...args: unknown[]): Promise<T> {
    const body = JSON.stringify({
      jsonrpc: "1.0",
      method: method.toLowerCase(),
      params: typeof args[0] === "object" ? args[0] : args,
    });
    const requestOptions = { method: "POST", headers, body };
    if (debug) {
      console.debug(body);
    }
    const parsedUrl = new URL(url);
    parsedUrl.pathname = "/wallet/" + walletName;
    return fetch(parsedUrl.toString(), requestOptions)
      .then((response) => {
        if (!response.ok) {
          throw new Error(response.statusText);
        }
        return response.json();
      })
      .then((response: { result: T; error?: Error }) => {
        if (response.error) {
          throw response.error;
        }
        return response.result satisfies T;
      });
  };
}

export async function sendBtc(args: {
  toAddress: string;
  amountInBtc: number | string;
  rpc: BtcCaller;
  data?: string;
}) {
  const { toAddress, amountInBtc, rpc, data } = args;
  const outputs = [{ [toAddress]: amountInBtc.toString() }];
  const fundOptions: { fee_rate: number; changePosition?: number } = {
    fee_rate: 25,
  };
  if (data) {
    outputs.push({ data });
    fundOptions.changePosition = 2;
  }
  const rawSendTx = await rpc("createrawtransaction", {
    inputs: [],
    outputs,
  });
  const fundedSendTx = await rpc<{ hex: string }>(
    "fundrawtransaction",
    rawSendTx,
    fundOptions
  );
  const signedSendTx = await rpc<{ hex: string }>(
    "signrawtransactionwithwallet",
    fundedSendTx.hex
  );
  return rpc<string>("sendrawtransaction", signedSendTx.hex);
}

export async function waitForBtcTransaction(args: {
  rpc: BtcCaller;
  hash: BytesLike;
  confirmations: number;
  interval: number;
}) {
  const { rpc, hash, confirmations, interval } = args;
  let tx: { confirmations: number; blockhash: string; hex: string } | undefined;
  while (!tx?.confirmations || confirmations > tx.confirmations) {
    tx = await rpc("gettransaction", hash);
    if (tx && confirmations > tx.confirmations) {
      console.info(
        `Waiting for transaction ${hash.toString()} (${tx.confirmations.toString()} confirmations)`
      );
      await sleep(interval);
    }
  }
  console.info("Transaction confirmed");
  return tx;
}
