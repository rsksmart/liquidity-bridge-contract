const LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
const LiquidityBridgeContractProxy = artifacts.require('LiquidityBridgeContractProxy');
const LiquidityBridgeContractAdmin = artifacts.require('LiquidityBridgeContractAdmin');
const Mock = artifacts.require('Mock')
const BridgeMock = artifacts.require('BridgeMock');
const SignatureValidator = artifacts.require('SignatureValidator');
const SignatureValidatorMock = artifacts.require('SignatureValidatorMock');

const RSK_NETWORK_MAINNET = 'rskMainnet';
const RSK_NETWORK_TESTNET = 'rskTestnet';
const RSK_NETWORK_REGTEST = 'rskRegtest';

const RSK_NETWORKS = [RSK_NETWORK_MAINNET, RSK_NETWORK_TESTNET, RSK_NETWORK_REGTEST];

const RSK_BRIDGE_ADDRESS = '0x0000000000000000000000000000000001000006';

const MINIMUM_COLLATERAL = "1"; // amount in wei
const MINIMUM_PEG_IN_DEFAULT = "5000000000000000"; // amount in wei
const MINIMUM_PEG_IN_REGTEST = "500000000000000000"; // amount in wei
const REWARD_PERCENTAGE = 10;
const RESIGN_DELAY_BLOCKS = 1;
const DUST_THRESHOLD = 2300 * 65164000;
const { deploy, read } = require('../config');

module.exports = async function (deployer, network) {

    let minimumPegIn, bridgeAddress;
    if (RSK_NETWORKS.includes(network)) { // deploy to actual networks so don't use mocks and use existing bridge.
        bridgeAddress = RSK_BRIDGE_ADDRESS;

        await deploy('SignatureValidator', network, async (state) => {
            await deployer.deploy(SignatureValidator);
            await deployer.link(SignatureValidator, LiquidityBridgeContract);
            const response = await SignatureValidator.deployed();
            state.address = response.address;
        });

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

        await deploy('SignatureValidator', network, async (state) => {
            await deployer.deploy(SignatureValidatorMock);
            const signatureValidatorMockInstance = await SignatureValidatorMock.deployed();
            await LiquidityBridgeContract.link('SignatureValidator', signatureValidatorMockInstance.address);
            state.address = signatureValidatorMockInstance.address;
        });

        minimumPegIn = 2;
    }

    await deploy('LiquidityBridgeContractAdmin', network, async (state) => {
        await deployer.deploy(LiquidityBridgeContractAdmin);
        const response = await LiquidityBridgeContractAdmin.deployed();
        state.address = response.address;
    });


    let config = read();
    config = await deploy('LiquidityBridgeContract', network, async (state) => {
        const signatureValidatorLib = await SignatureValidator.at(config[network]['SignatureValidator'].address);
        await deployer.link(signatureValidatorLib, LiquidityBridgeContract);
        await deployer.deploy(LiquidityBridgeContract);
        const response = await LiquidityBridgeContract.deployed();
        state.address = response.address;
    });

    const liquidityBridgeContractInstance = await LiquidityBridgeContract.at(config[network]['LiquidityBridgeContract'].address);

    const lbcLogic = new web3.eth.Contract(liquidityBridgeContractInstance.abi, liquidityBridgeContractInstance.address);

    const methodCall = await lbcLogic.methods.initialize(
        bridgeAddress,
        MINIMUM_COLLATERAL,
        minimumPegIn,
        REWARD_PERCENTAGE,
        RESIGN_DELAY_BLOCKS,
        DUST_THRESHOLD
    );

    methodCall.call({ from: deployer.address });

    await deploy('LiquidityBridgeContractProxy', network, async (state) => {
        await deployer.deploy(LiquidityBridgeContractProxy, liquidityBridgeContractInstance.address, config[network]['LiquidityBridgeContractAdmin'].address, methodCall.encodeABI());
        const response = await LiquidityBridgeContractProxy.deployed();
        state.address = response.address;
    });
};