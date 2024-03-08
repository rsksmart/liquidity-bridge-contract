const { upgradeProxy } = require("@openzeppelin/truffle-upgrades");

const SignatureValidator = artifacts.require("SignatureValidator");
const QuotesV2 = artifacts.require("QuotesV2");
const LiquidityBridgeContractV2 = artifacts.require('LiquidityBridgeContractV2.sol');
const BtcUtils = artifacts.require("BtcUtils");

const { read, deploy} = require("../config");

// using LP address as placeholder for now
const FEE_COLLECTOR_MAINNET_ADDRESS = '0x4202BAC9919C3412fc7C8BE4e678e26279386603'.toLowerCase();
const FEE_COLLECTOR_TESTNET_ADDRESS = '0x86B6534687A176A476C16083a373fB9Fe4FAb449'
const DAO_FEE_PERCENTAGE = 0

module.exports = async function (deployer, network, accounts) {
    let config = read();

    const signatureValidatorLib = await SignatureValidator.at(
        config[network]["SignatureValidator"].address
    );
    await deployer.link(signatureValidatorLib, LiquidityBridgeContractV2);

    await deployer.deploy(QuotesV2);
    await deployer.link(QuotesV2, LiquidityBridgeContractV2);
    const quotesInstance = await QuotesV2.deployed();
    console.log("QuotesV2 deployed at:", quotesInstance.address);

    const btcUtilsLib = await BtcUtils.at(
        config[network]["BtcUtils"].address
    );
    await deployer.link(btcUtilsLib, LiquidityBridgeContractV2);

    const existing = config[network]["LiquidityBridgeContract"];

    console.log('Upgrading contract ', existing.address)
    const response = await upgradeProxy(
        existing.address,
        LiquidityBridgeContractV2,
        { deployer, unsafeAllowLinkedLibraries: true }
    );

    let daoFeeCollectorAddress = '';

    if(network === 'ganache' || network === 'rskRegtest' || network === 'test') {
        daoFeeCollectorAddress = accounts[8];
    } else if(network === 'rskTestnet' || network === 'rskDevelopment') {
        daoFeeCollectorAddress = FEE_COLLECTOR_TESTNET_ADDRESS;
    } else if(network === 'rskMainnet'){
        daoFeeCollectorAddress = FEE_COLLECTOR_MAINNET_ADDRESS;
    } else {
        throw new Error('Unknown network');
    }

    await response.initializeV2(DAO_FEE_PERCENTAGE, daoFeeCollectorAddress);

    console.log("Upgraded", response.address);
};
