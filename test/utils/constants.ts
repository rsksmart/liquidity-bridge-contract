import { ethers } from "hardhat";
import { LiquidityBridgeContractV2 } from "../../typechain-types";
import * as bs58check from "bs58check";

export const BRIDGE_ADDRESS = "0x0000000000000000000000000000000001000006";

export const LP_COLLATERAL = ethers.parseEther("1.5");

export const MIN_COLLATERAL_TEST = ethers.parseEther("0.03");

export const TEST_FED_ADDRESS = "2N5muMepJizJE1gR7FbHJU6CD18V3BpNF9p";

export const P2PKH_ZERO_ADDRESS_TESTNET = "mfWxJ45yp2SFn7UciZyNpvDKrzbhyfKrY8";

export const TEST_P2PKH_ADDRESS = "mtwn2DFCfiJ75ppTYvAULs1v3nqyKo5Dnn";

export const DECODED_P2PKH_ZERO_ADDRESS_TESTNET = bs58check.decode(
  P2PKH_ZERO_ADDRESS_TESTNET
);

export const DECODED_TEST_FED_ADDRESS = bs58check.decode(TEST_FED_ADDRESS);

export const DECODED_TEST_P2PKH_ADDRESS = bs58check.decode(TEST_P2PKH_ADDRESS);

export const ZERO_ADDRESS = "0x" + "00".repeat(20);

export const anyHex = "0x" + "ff".repeat(32);

export const anyNumber = 10;

export type RegisterLpParams = Parameters<
  LiquidityBridgeContractV2["register"]
>;
export const REGISTER_LP_PARAMS: RegisterLpParams = [
  "First contract",
  "http://localhost/api",
  true,
  "both",
  { value: LP_COLLATERAL },
];

export const PEGOUT_CONSTANTS = {
  TEST_DUST_THRESHOLD: ethers.parseEther("0.0000001"),
  TEST_BTC_BLOCK_TIME: 3600,
} as const;

export const PEGIN_CONSTANTS = {
  TEST_DUST_THRESHOLD: 2300n * 65164000n,
  TEST_MIN_PEGIN: ethers.parseEther("0.5"),
  RAW_TRANSACTION_MOCK: "0x112233",
  PMT_MOCK: "0x010203",
  HEIGHT_MOCK: 10,
  BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR: -303,
  BRIDGE_REFUNDED_USER_ERROR_CODE: -100,
  BRIDGE_REFUNDED_LP_ERROR_CODE: -200,
} as const;

export const COLLATERAL_CONSTANTS = {
  TEST_DEFAULT_ADMIN_DELAY: 30n,
  TEST_MIN_COLLATERAL: ethers.parseEther("0.6"),
  TEST_RESIGN_DELAY_BLOCKS: 500n,
  TEST_REWARD_PERCENTAGE: 10n,
} as const;

export enum ProviderType {
  PegIn,
  PegOut,
  Both,
}

export enum PegInStates {
  UNPROCESSED_QUOTE,
  CALL_DONE,
  PROCESSED_QUOTE,
}
