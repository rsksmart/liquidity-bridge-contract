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
        derivationPath: "m/44'/37310'/0'/0/"
      }),
      network_id: 31,
      gasPrice: 6000000000,
    },
    rskMainnet: {
      provider: () => new HDWalletProvider({
        mnemonic,
        providerOrUrl: `https://public-node.rsk.co`,
        derivationPath: "m/44'/137'/0'/0/"
      }),
      network_id: 30,
      gasPrice: 60000000,
    },
    testRegtest: {
      host: '127.0.0.1',
      port: 4444,
      network_id: 33,
    },
  },
  compilers: {
    solc: {
        version : "0.8.3",
        settings: {          // See the solidity docs for advice about optimization and evmVersion
          optimizer: {
            enabled: true,
            runs: 200
          },
          evmVersion: "byzantium"
        }
    }
  }
}
