import * as bs58check from "bs58check";
import { bech32, bech32m } from "bech32";
import { BytesLike } from "ethers";
import { QuotesV2 } from "../../typechain-types";

export interface ApiPeginQuote {
  fedBTCAddr: string;
  lbcAddr: string;
  lpRSKAddr: string;
  btcRefundAddr: string;
  rskRefundAddr: string;
  lpBTCAddr: string;
  callFee: number;
  penaltyFee: number;
  contractAddr: string;
  data: string;
  gasLimit: number;
  nonce: string;
  value: string;
  agreementTimestamp: number;
  timeForDeposit: number;
  lpCallTime: number;
  confirmations: number;
  callOnRegister: boolean;
  gasFee: number;
  productFeeAmount: number;
}

export interface ApiPegoutQuote {
  lbcAddress: string;
  liquidityProviderRskAddress: string;
  btcRefundAddress: string;
  rskRefundAddress: string;
  lpBtcAddr: string;
  callFee: number;
  penaltyFee: number;
  nonce: string;
  depositAddr: string;
  value: string;
  agreementTimestamp: number;
  depositDateLimit: number;
  transferTime: number;
  depositConfirmations: number;
  transferConfirmations: number;
  productFeeAmount: number;
  gasFee: number;
  expireBlocks: number;
  expireDate: number;
}

export function parsePeginQuote(
  quote: ApiPeginQuote
): QuotesV2.PeginQuoteStruct {
  return {
    fedBtcAddress: bs58check.decode(quote.fedBTCAddr).slice(1),
    lbcAddress: quote.lbcAddr.toLowerCase(),
    liquidityProviderRskAddress: quote.lpRSKAddr.toLowerCase(),
    btcRefundAddress: bs58check.decode(quote.btcRefundAddr),
    rskRefundAddress: quote.rskRefundAddr.toLowerCase(),
    liquidityProviderBtcAddress: bs58check.decode(quote.lpBTCAddr),
    callFee: quote.callFee,
    penaltyFee: quote.penaltyFee,
    contractAddress: quote.contractAddr.toLowerCase(),
    data: quote.data,
    gasLimit: quote.gasLimit,
    nonce: quote.nonce,
    value: quote.value,
    agreementTimestamp: quote.agreementTimestamp,
    timeForDeposit: quote.timeForDeposit,
    callTime: quote.lpCallTime,
    depositConfirmations: quote.confirmations,
    callOnRegister: quote.callOnRegister,
    gasFee: quote.gasFee,
    productFeeAmount: quote.productFeeAmount,
  };
}

export function parsePegoutQuote(
  quote: ApiPegoutQuote
): QuotesV2.PegOutQuoteStruct {
  return {
    lbcAddress: quote.lbcAddress.toLowerCase(),
    lpRskAddress: quote.liquidityProviderRskAddress.toLowerCase(),
    btcRefundAddress: parseBtcAddress(quote.btcRefundAddress),
    rskRefundAddress: quote.rskRefundAddress.toLowerCase(),
    lpBtcAddress: bs58check.decode(quote.lpBtcAddr),
    callFee: quote.callFee,
    penaltyFee: quote.penaltyFee,
    nonce: quote.nonce,
    deposityAddress: parseBtcAddress(quote.depositAddr),
    value: quote.value,
    agreementTimestamp: quote.agreementTimestamp,
    depositDateLimit: quote.depositDateLimit,
    transferTime: quote.transferTime,
    depositConfirmations: quote.depositConfirmations,
    transferConfirmations: quote.transferConfirmations,
    productFeeAmount: quote.productFeeAmount,
    gasFee: quote.gasFee,
    expireBlock: quote.expireBlocks,
    expireDate: quote.expireDate,
  };
}

function parseBtcAddress(address: string): BytesLike {
  const MAINNET_P2TR = /^bc1p([ac-hj-np-z02-9]{58})$/;
  const TESTNET_P2TR = /^tb1p([ac-hj-np-z02-9]{58})$/;
  const REGTEST_P2TR = /^bcrt1p([ac-hj-np-z02-9]{58})$/;

  const MAINNET_P2WSH = /^bc1q([ac-hj-np-z02-9]{58})$/;
  const TESTNET_P2WSH = /^tb1q([ac-hj-np-z02-9]{58})$/;
  const REGTEST_P2WSH = /^bcrt1q([ac-hj-np-z02-9]{58})$/;

  const MAINNET_P2WPKH = /^bc1q([ac-hj-np-z02-9]{38})$/;
  const TESTNET_P2WPKH = /^tb1q([ac-hj-np-z02-9]{38})$/;
  const REGTEST_P2WPKH = /^bcrt1q([ac-hj-np-z02-9]{38})$/;

  const MAINNET_P2SH = /^3([a-km-zA-HJ-NP-Z1-9]{33,34})$/;
  const TESTNET_P2SH = /^2([a-km-zA-HJ-NP-Z1-9]{33,34})$/;

  const MAINNET_P2PKH = /^1([a-km-zA-HJ-NP-Z1-9]{25,34})$/;
  const TESTNET_P2PKH = /^[mn]([a-km-zA-HJ-NP-Z1-9]{25,34})$/;

  const bech32mRegex = [MAINNET_P2TR, TESTNET_P2TR, REGTEST_P2TR];
  const bech32Regex = [
    MAINNET_P2WSH,
    TESTNET_P2WSH,
    REGTEST_P2WSH,
    MAINNET_P2WPKH,
    TESTNET_P2WPKH,
    REGTEST_P2WPKH,
  ];
  const base58Regex = [
    MAINNET_P2SH,
    TESTNET_P2SH,
    MAINNET_P2PKH,
    TESTNET_P2PKH,
  ];

  if (bech32mRegex.some((regex) => regex.test(address))) {
    return new Uint8Array(bech32m.decode(address).words);
  } else if (bech32Regex.some((regex) => regex.test(address))) {
    return new Uint8Array(bech32.decode(address).words);
  } else if (base58Regex.some((regex) => regex.test(address))) {
    return bs58check.decode(address);
  } else {
    throw new Error("Invalid btc address type");
  }
}
