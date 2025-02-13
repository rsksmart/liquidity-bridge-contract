require('dotenv').config()
const HDWalletProvider = require('@truffle/hdwallet-provider');

const fs = require('fs');
let mnemonic;
try {
  mnemonic = fs.readFileSync(".secret").toString().trim();
} catch (e) {
  mnemonic = 'INVALID';
}

module.exports = {
  mocha: {
    enableTimeouts: false,
    timeout: 1000000
  },
  plugins: ["truffle-contract-size"],
  networks: {
    ganache: {
      host: '127.0.0.1',
      port: 7545,
      network_id: 5777,
      gas: 200000000
    },
    rskRegtest: {
      host: '127.0.0.1',
      port: 4444,
      network_id: 33,
    },
    alphanet: {
      provider: () => new HDWalletProvider({
        mnemonic,
        providerOrUrl: process.env.ALPHANET_RPC_URL,
        derivationPath: "m/44'/60'/0'/0/",
        pollingInterval: 30000,
      }),
      port: 4444,
      network_id: 78
    },
    rskDevelopment: {
      provider: () => new HDWalletProvider({
        privateKeys: [process.env.DEV_SIGNER_PRIVATE_KEY],
        providerOrUrl: process.env.TESTNET_RPC_URL,
        derivationPath: "m/44'/60'/0'/0/",
        pollingInterval: 30000,
      }),
      network_id: 31,
      deploymentPollingInterval: 30000,
      networkCheckTimeout: 10000,
      timeoutBlocks: 200
    },
    rskTestnet: {
      provider: () => new HDWalletProvider({
        mnemonic,
        providerOrUrl: process.env.TESTNET_RPC_URL,
        derivationPath: "m/44'/37310'/0'/0/",
        pollingInterval: 30000,
      }),
      network_id: 31,
      deploymentPollingInterval: 30000,
      networkCheckTimeout: 10000,
      timeoutBlocks: 200
    },
    rskMainnet: {
      provider: () => new HDWalletProvider({
        privateKeys: [process.env.MAINNET_SIGNER_PRIVATE_KEY],
        providerOrUrl: process.env.MAINNET_RPC_URL,
        derivationPath: "m/44'/137'/0'/0/",
        pollingInterval: 30000,
      }),
      network_id: 30,
      deploymentPollingInterval: 30000,
      networkCheckTimeout: 10000,
      timeoutBlocks: 200
    }
  },
  compilers: {
    solc: {
        version : "0.8.18",
        settings: {          // See the solidity docs for advice about optimization and evmVersion
          optimizer: {
            enabled: true,
            runs: 1
          },
          // evmVersion: "byzantium"
        }
    }
  }
}
