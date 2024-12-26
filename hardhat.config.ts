import dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "./tasks/get-versions";
import "./tasks/btc-best-height";
import "./tasks/hash-quote";
import "./tasks/refund-user-pegout";
import "./tasks/register-pegin";

dotenv.config();

const {
  MAINNET_RPC_URL,
  TESTNET_RPC_URL,
  MAINNET_SIGNER_PRIVATE_KEY,
  MAINNET_MNEMONIC,
  TESTNET_SIGNER_PRIVATE_KEY,
  TESTNET_MNEMONIC,
  DEV_SIGNER_PRIVATE_KEY,
  DEV_MNEMONIC,
} = process.env;

const rskMainnetDerivationPath = "m/44'/137'/0'/0/0";
const rskTestnetDerivationPath = "m/44'/37310'/0'/0/0";

const rpcDefaultTimeout = 3 * 60 * 1000; // 3 minutes

const config: HardhatUserConfig = {
  networks: {
    rskRegtest: {
      url: "http://localhost:4444",
      chainId: 33,
    },
    rskDevelopment: {
      url: TESTNET_RPC_URL,
      timeout: rpcDefaultTimeout,
      chainId: 31,
      accounts: getAccounts("development"),
    },
    rskTestnet: {
      url: TESTNET_RPC_URL,
      timeout: rpcDefaultTimeout,
      chainId: 31,
      accounts: getAccounts("testnet"),
    },
    rskMainnet: {
      url: MAINNET_RPC_URL,
      timeout: rpcDefaultTimeout,
      chainId: 30,
      accounts: getAccounts("mainnet"),
    },
  },
  solidity: {
    version: "0.8.18",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1,
      },
    },
  },
};

export default config;

function getAccounts(network: "mainnet" | "testnet" | "development") {
  switch (network) {
    case "mainnet":
      return getMainnetAccounts();
    case "testnet":
      return getTestnetAccounts();
    case "development":
      return getDevAccounts();
    default:
      return undefined;
  }
}

function getMainnetAccounts() {
  if (MAINNET_MNEMONIC) {
    return {
      mnemonic: MAINNET_MNEMONIC,
      path: rskMainnetDerivationPath,
    };
  } else if (MAINNET_SIGNER_PRIVATE_KEY) {
    return [MAINNET_SIGNER_PRIVATE_KEY];
  } else {
    return undefined;
  }
}

function getTestnetAccounts() {
  if (TESTNET_MNEMONIC) {
    return {
      mnemonic: TESTNET_MNEMONIC,
      path: rskTestnetDerivationPath,
    };
  } else if (TESTNET_SIGNER_PRIVATE_KEY) {
    return [TESTNET_SIGNER_PRIVATE_KEY];
  } else {
    return undefined;
  }
}

function getDevAccounts() {
  if (DEV_MNEMONIC) {
    return {
      mnemonic: DEV_MNEMONIC,
      path: rskTestnetDerivationPath,
    };
  } else if (DEV_SIGNER_PRIVATE_KEY) {
    return [DEV_SIGNER_PRIVATE_KEY];
  } else {
    return undefined;
  }
}