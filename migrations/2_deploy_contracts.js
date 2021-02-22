var LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
var Mock = artifacts.require('Mock')
var BridgeMock = artifacts.require('BridgeMock');

module.exports = function(deployer, network) {
   /*if (network == 'test') { //used for running truffle tests
        deployer.deploy(BridgeMock).then((mockInstance) => {
            let bridgeAddress = mockInstance.address;
            deployer.deploy(LiquidityBridgeContract, bridgeAddress);
        });
    } else {
        deployer.deploy(LiquidityBridgeContract, '0x0000000000000000000000000000000001000006');
    }*/

    deployer.deploy(BridgeMock).then((mockInstance) => {
                let bridgeAddress = mockInstance.address;
                deployer.deploy(LiquidityBridgeContract, bridgeAddress, 1);
    });
    deployer.deploy(Mock);
};
