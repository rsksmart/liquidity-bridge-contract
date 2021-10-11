var LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
var Mock = artifacts.require('Mock')
var BridgeMock = artifacts.require('BridgeMock');
var SafeMath = artifacts.require('SafeMath');

module.exports = async function(deployer, network) {
   if (network == 'testnet') { //used for running truffle tests
        await deployer.deploy(BridgeMock);
        const mockInstance = await BridgeMock.deployed(); // get the deployed instance of A

        let bridgeAddress = mockInstance.address;
        await deployer.deploy(SafeMath);
        await deployer.link(SafeMath, LiquidityBridgeContract);
        await deployer.deploy(LiquidityBridgeContract, bridgeAddress, 1, 10, 1, 2300 * 65164000);
        deployer.deploy(Mock);
    } else {
        args = process.argv[2].split(" ");
        await deployer.deploy(SafeMath)
        await deployer.link(SafeMath, LiquidityBridgeContract);
        deployer.deploy(LiquidityBridgeContract, '0x0000000000000000000000000000000001000006', parseInt(args[args.length - 1]), 10, 1, 2300 * 65164000);
    }    
};
