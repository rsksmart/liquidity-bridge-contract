var LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
var Mock = artifacts.require('Mock')
var BridgeMock = artifacts.require('BridgeMock');
var SafeMath = artifacts.require('SafeMath');
var SignatureValidator = artifacts.require('SignatureValidator');
var SignatureValidatorMock = artifacts.require('SignatureValidatorMock');

module.exports = async function(deployer, network) {
    await deployer.deploy(SafeMath);
    await deployer.link(SafeMath, LiquidityBridgeContract);
    await deployer.deploy(SignatureValidator);

    if (network == 'rskTestnet' || network == 'rskMainnet') {   // deploy to actual networks so don't use mocks and use existing bridge.   
        const validatorInstance = await SignatureValidator.deployed();

        await deployer.deploy(LiquidityBridgeContract, '0x0000000000000000000000000000000001000006', 1, 10, 1, 2300 * 65164000, validatorInstance.address);

    } else { // test with mocks;
        await deployer.deploy(BridgeMock);
        const bridgeMockInstance = await BridgeMock.deployed();

        await deployer.deploy(SignatureValidatorMock);
        const validatorInstance = await SignatureValidatorMock.deployed();

        await deployer.deploy(LiquidityBridgeContract, bridgeMockInstance.address, 1, 10, 1, 2300 * 65164000, validatorInstance.address);
        await deployer.deploy(Mock);
    }    
};
