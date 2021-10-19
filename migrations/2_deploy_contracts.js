var LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
var Mock = artifacts.require('Mock')
var BridgeMock = artifacts.require('BridgeMock');
var SafeMath = artifacts.require('SafeMath');

module.exports = async function(deployer, network) {
   if (network == 'testnet') {
        await deployer.deploy(BridgeMock);
        const mockInstance = await BridgeMock.deployed();
        let bridgeAddress = mockInstance.address;
        
        await deployer.deploy(SafeMath);
        await deployer.link(SafeMath, LiquidityBridgeContract);
        await deployer.deploy(LiquidityBridgeContract, bridgeAddress, 1, 10, 1, 2300 * 65164000);
        await deployer.deploy(Mock);
    } else {
        await deployer.deploy(BridgeMock);
        const mockInstance = await BridgeMock.deployed();
        let bridgeAddress = mockInstance.address;

        await deployer.deploy(SafeMath)
        await deployer.link(SafeMath, LiquidityBridgeContract);
        await deployer.deploy(LiquidityBridgeContract, bridgeAddress, 1, 10, 1, 2300 * 65164000);
        await deployer.deploy(Mock);
    }    
};
