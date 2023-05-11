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
  plugins: ["solidity-coverage"],
  networks: {
    rskRegtest: {
      host: '127.0.0.1',
      port: 4444,
      network_id: 33,
    },
    rskTestnet: {
      provider: () => new HDWalletProvider({
        mnemonic,
        providerOrUrl: `https://public-node.testnet.rsk.co`,
        derivationPath: "m/44'/60'/0'/0/",
        pollingInterval: 30000,
      }),
      network_id: 31,
      gasPrice: 65164000,
      deploymentPollingInterval: 30000,
    },
    rskMainnet: {
      provider: () => new HDWalletProvider({
        mnemonic,
        providerOrUrl: `https://public-node.rsk.co`,
        derivationPath: "m/44'/137'/0'/0/",
        pollingInterval: 30000,
      }),
      network_id: 30,
      gasPrice: 65164000,
      deploymentPollingInterval: 30000,
    }
  },
  compilers: {
    solc: {
        version : "0.8.3",
        settings: {          // See the solidity docs for advice about optimization and evmVersion
          optimizer: {
            enabled: true,
            runs: 1
          },
          evmVersion: "byzantium"
        }
    }
  }
}
