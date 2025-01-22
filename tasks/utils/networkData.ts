export const networkData = {
  rskTestnet: {
    owners: [
      "0x8E925445BdA88C9F980976dB098Cb1c450BFc719",
      "0x452A22889229b87472Cd77d4f2A8aA33b223D6B5",
    ],
    lbcProxyAddress: "0x4B6E7420F0e22472BFF01309A9BE96eab3a7f004",
    lbcProxyAdminAddress: "0x4B6E7420F0e22472BFF01309A9BE96eab3a7f004",
    providerRpc: process.env.TESTNET_RPC_URL,
    mnemonic: process.env.TESTNET_MNEMONIC,
  },
  rskMainnet: {
    owners: [
      "0x8E925445BdA88C9F980976dB098Cb1c450BFc719",
      "0x452A22889229b87472Cd77d4f2A8aA33b223D6B5",
    ],
    lbcProxyAddress: "0xAA9cAf1e3967600578727F975F283446A3Da6612",
    lbcProxyAdminAddress: "0x9dB9edEC34280D4DF6A80dDE6Cb3e80455657d3E",
    providerRpc: process.env.MAINNET_RPC_URL,
    mnemonic: process.env.MAINNET_MNEMONIC,
  },
  hardhat: {
    owners: ["s1", "s2"],
    lbcProxyAddress: "0x0000000000000000000000000000000000000000",
    lbcProxyAdminAddress: "0x0000000000000000000000000000000000000000",
    providerRpc: "http://localhost:8545",
    mnemonic: "test test test test test test test test test test test junk",
  },
};
