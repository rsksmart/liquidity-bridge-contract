const { forceImport } = require('@openzeppelin/truffle-upgrades');
const LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');

module.exports = async function (deployer) {
    const proxyAddress = "0xc2A630c053D12D63d32b025082f6Ba268db18300";
    await forceImport(proxyAddress, LiquidityBridgeContract, { deployer });
};
