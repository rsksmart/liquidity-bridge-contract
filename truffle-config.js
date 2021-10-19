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
    testnet: {
      provider: () => new HDWalletProvider(mnemonic, 'https://public-node.testnet.rsk.co/1.1.0'),
      network_id: 31,
      gasPrice: 6000000000,
    },
  },
  compilers: {
    solc: {
        version : "0.8.3"
    }
  }
}
