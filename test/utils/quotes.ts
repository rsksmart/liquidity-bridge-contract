import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { QuotesV2 } from "../../typechain-types";
import {
  DECODED_P2PKH_ZERO_ADDRESS_TESTNET,
  DECODED_TEST_FED_ADDRESS,
  DECODED_TEST_P2PKH_ADDRESS,
} from "./constants";
import { randomBytes } from "crypto";
import { BigNumberish, BytesLike } from "ethers";
import { toLeHex } from "./encoding";
import { BtcAddressType, getTestBtcAddress } from "./btc";
import { Quotes } from "../../typechain-types/contracts/libraries";

const now = () => Math.floor(Date.now() / 1000); // ms to s

export function getTestPeginQuote(args: {
  lbcAddress: string;
  liquidityProvider: HardhatEthersSigner;
  value: BigNumberish;
  destinationAddress: string;
  refundAddress: string;
  data?: BytesLike;
  productFeePercentage?: number;
}): QuotesV2.PeginQuoteStruct & Quotes.PegInQuoteStruct {
  // TODO if at some point DAO integration is re activated, this default value should be updated to not be 0
  const productFeePercentage = args.productFeePercentage ?? 0;
  const productFee = (BigInt(productFeePercentage) * BigInt(args.value)) / 100n;

  const quote: QuotesV2.PeginQuoteStruct = {
    fedBtcAddress: DECODED_TEST_FED_ADDRESS.slice(1), // remove version byte
    lbcAddress: args.lbcAddress,
    liquidityProviderRskAddress: args.liquidityProvider.address,
    btcRefundAddress: DECODED_P2PKH_ZERO_ADDRESS_TESTNET,
    rskRefundAddress: args.refundAddress,
    liquidityProviderBtcAddress: DECODED_TEST_P2PKH_ADDRESS,
    callFee: "100000000000000",
    penaltyFee: "10000000000000",
    contractAddress: args.destinationAddress,
    data: args.data ?? "0x",
    gasLimit: 21000,
    nonce: BigInt("0x" + randomBytes(7).toString("hex")),
    value: args.value,
    agreementTimestamp: now(),
    timeForDeposit: 3600,
    callTime: 7200,
    depositConfirmations: 10,
    callOnRegister: false,
    productFeeAmount: productFee,
    gasFee: 100,
  };
  return quote;
}

export function getTestPegoutQuote(args: {
  lbcAddress: string;
  liquidityProvider: HardhatEthersSigner;
  refundAddress: string;
  value: BigNumberish;
  destinationAddressType?: BtcAddressType;
  productFeePercentage?: number;
}): QuotesV2.PegOutQuoteStruct & Quotes.PegOutQuoteStruct {
  // TODO if at some point DAO integration is re activated, this default value should be updated to not be 0
  const productFeePercentage = args.productFeePercentage ?? 0;
  const productFee = (BigInt(productFeePercentage) * BigInt(args.value)) / 100n;
  const destinationAddressType = args.destinationAddressType ?? "p2pkh";
  const nowTimestamp = now();

  // TODO this is to support both legacy and new test suite, once we adapt the legacy suite we can remove this union
  const quote: QuotesV2.PegOutQuoteStruct & Quotes.PegOutQuoteStruct = {
    lbcAddress: args.lbcAddress,
    lpRskAddress: args.liquidityProvider.address,
    btcRefundAddress: DECODED_P2PKH_ZERO_ADDRESS_TESTNET,
    rskRefundAddress: args.refundAddress,
    lpBtcAddress: DECODED_TEST_P2PKH_ADDRESS,
    callFee: "100000000000000",
    penaltyFee: "10000000000000",
    deposityAddress: getTestBtcAddress(destinationAddressType),
    depositAddress: getTestBtcAddress(destinationAddressType),
    nonce: BigInt("0x" + randomBytes(7).toString("hex")),
    value: args.value,
    agreementTimestamp: nowTimestamp,
    depositDateLimit: nowTimestamp + 600,
    transferTime: 3600,
    depositConfirmations: 10,
    transferConfirmations: 2,
    productFeeAmount: productFee,
    gasFee: 100,
    expireBlock: 4000,
    expireDate: nowTimestamp + 7200,
  };
  return quote;
}

/**
 * Get the total value of a pegin or pegout quote
 * @param quote The quote to get the total value of
 * @returns { bigint } The total value of the quote
 */
export function totalValue(
  quote: QuotesV2.PeginQuoteStruct | QuotesV2.PegOutQuoteStruct
): bigint {
  return (
    BigInt(quote.value) +
    BigInt(quote.callFee) +
    BigInt(quote.productFeeAmount) +
    BigInt(quote.gasFee)
  );
}

/**
 * Get mock bitcoin block headers for the given quote
 * @param args.quote The quote to get the block headers for
 * @param args.firstConfirmationSeconds The time in seconds for the first confirmation
 * @param args.nConfirmationSeconds The time in seconds for the n-th confirmation
 * @returns { firstConfirmationHeader, nConfirmationHeader } The block headers for the first and n-th confirmations.
 * Their only populated field will be the block timestamp
 */
export function getBtcPaymentBlockHeaders(args: {
  quote: QuotesV2.PeginQuoteStruct | QuotesV2.PegOutQuoteStruct;
  firstConfirmationSeconds: number;
  nConfirmationSeconds: number;
}) {
  const { quote, firstConfirmationSeconds, nConfirmationSeconds } = args;
  const firstConfirmationTime = toLeHex(
    Number(quote.agreementTimestamp) + firstConfirmationSeconds
  );
  const nConfirmationTime = toLeHex(
    Number(quote.agreementTimestamp) + nConfirmationSeconds
  );

  const firstConfirmationHeader =
    "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
    firstConfirmationTime +
    "0000000000000000";
  const nConfirmationHeader =
    "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
    nConfirmationTime +
    "0000000000000000";
  return { firstConfirmationHeader, nConfirmationHeader };
}
