const { upgradeProxy } = require("@openzeppelin/truffle-upgrades");

const SignatureValidator = artifacts.require("SignatureValidator");
const QuotesV1 = artifacts.require("QuotesV1");
const LiquidityBridgeContractV1 = artifacts.require('LiquidityBridgeContractV1');
const BtcUtils = artifacts.require("BtcUtils");

const { read, deploy} = require("../config");

module.exports = async function (deployer, network, accounts) {
    let config = read();

    const signatureValidatorLib = await SignatureValidator.at(
        config[network]["SignatureValidator"].address
    );
    await deployer.link(signatureValidatorLib, LiquidityBridgeContractV1);

    await deployer.deploy(QuotesV1);
    const quotesInstance = await QuotesV1.deployed();
    await LiquidityBridgeContractV1.link("QuotesV1", quotesInstance.address);
    const quotesLib = await QuotesV1.at(
        quotesInstance.address
    );
    await deployer.link(quotesLib, LiquidityBridgeContractV1);

    const btcUtilsLib = await BtcUtils.at(
        config[network]["BtcUtils"].address
    );
    await deployer.link(btcUtilsLib, LiquidityBridgeContractV1);

    const existing = config[network]["LiquidityBridgeContract"];

    console.log('Upgrading contract ', existing.address)
    const response = await upgradeProxy(
        existing.address,
        LiquidityBridgeContractV1,
        { deployer, unsafeAllowLinkedLibraries: true }
    );

    let daoFeeCollectorAddress = '';

    if(network === 'ganache' || network === 'rskRegtest') {
        daoFeeCollectorAddress = accounts[9];
    } else if(network === '') {
        daoFeeCollectorAddress = '0x438A3641d53552EFBaB487c5894a78A1434F5aC9';
    }

    await response.initializeV1(1, daoFeeCollectorAddress);

    console.log("Upgraded", response.address);
};
