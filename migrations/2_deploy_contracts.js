var LiquidityBridgeContract = artifacts.require('LiquidityBridgeContractImpl');
var Mock = artifacts.require('Mock')
//var BridgeMock = artifacts.require('BridgeMock');

module.exports = function(deployer, network) {
   /* if (network == 'test') { //used for running truffle tests
        deployer.deploy(BridgeMock).then((mockInstance) => {
            let bridgeAddress = mockInstance.address;
            return deployer.deploy(LiquidityBridgeContract, bridgeAddress);
        });
    } else {
        deployer.deploy(LiquidityBridgeContract, '0x0000000000000000000000000000000001000006');
    }*/
    deployer.deploy(LiquidityBridgeContract, '0x0000000000000000000000000000000001000006');
    deployer.deploy(Mock);
};
