const LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
const Mock = artifacts.require('Mock')
const BridgeMock = artifacts.require('BridgeMock');
const SafeMath = artifacts.require('SafeMath');
const SignatureValidator = artifacts.require('SignatureValidator');
const SignatureValidatorMock = artifacts.require('SignatureValidatorMock');

const RSK_NETWORK_MAINNET = 'rskMainnet';
const RSK_NETWORK_TESTNET = 'rskTestnet';
const RSK_NETWORK_REGTEST = 'rskRegtest';

const RSK_NETWORKS = [RSK_NETWORK_MAINNET, RSK_NETWORK_TESTNET, RSK_NETWORK_REGTEST];

const RSK_BRIDGE_ADDRESS = '0x0000000000000000000000000000000001000006';

const MINIMUM_COLLATERAL = 1;
const MINIMUM_PEG_IN_DEFAULT = 500_000 * (10 ** 10); // amount in wei
const MINIMUM_PEG_IN_REGTEST = 50_000_000 * (10 ** 10); // amount in wei
const REWARD_PERCENTAGE = 10;
const RESIGN_DELAY_BLOCKS = 1;
const DUST_THRESHOLD = 2300 * 65164000;

module.exports = async function(deployer, network) {
    await deployer.deploy(SafeMath);
    await deployer.link(SafeMath, LiquidityBridgeContract);
    await deployer.deploy(SignatureValidator);
    
    let minimumPegIn, bridgeAddress, validatorAddress;
    if (RSK_NETWORKS.includes(network)) { // deploy to actual networks so don't use mocks and use existing bridge.
        bridgeAddress = RSK_BRIDGE_ADDRESS;
        
        const validatorInstance = await SignatureValidator.deployed();
        validatorAddress = validatorInstance.address;
        
        if (network === RSK_NETWORK_REGTEST) {
            minimumPegIn = MINIMUM_PEG_IN_REGTEST;
        } else {
            minimumPegIn = MINIMUM_PEG_IN_DEFAULT;
        }
    } else { // test with mocks;
        await deployer.deploy(Mock);
        
        await deployer.deploy(BridgeMock);
        const bridgeMockInstance = await BridgeMock.deployed();
        bridgeAddress = bridgeMockInstance.address;

        await deployer.deploy(SignatureValidatorMock);
        const validatorInstance = await SignatureValidatorMock.deployed();
        validatorAddress = validatorInstance.address;

        minimumPegIn = 2;
    }
    
    await deployer.deploy(LiquidityBridgeContract, bridgeAddress, MINIMUM_COLLATERAL, minimumPegIn, REWARD_PERCENTAGE, RESIGN_DELAY_BLOCKS, DUST_THRESHOLD, validatorAddress);
};
