var LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
var Mock = artifacts.require('Mock')
var BridgeMock = artifacts.require('BridgeMock');

module.exports = function(deployer, network) {
   if (network == 'testnet') { //used for running truffle tests
        deployer.deploy(BridgeMock).then((mockInstance) => {
            let bridgeAddress = mockInstance.address;
            deployer.deploy(LiquidityBridgeContract, bridgeAddress, 1, 10, 1, 2300 * 65164000);
        });
        deployer.deploy(Mock);
    } else {
        args = process.argv[2].split(" ");
        deployer.deploy(LiquidityBridgeContract, '0x0000000000000000000000000000000001000006', parseInt(args[args.length - 1]), 10, 1, 2300 * 65164000);
    }    
};
