const { upgradeProxy } = require("@openzeppelin/truffle-upgrades");

const SignatureValidator = artifacts.require("SignatureValidator");
const QuotesV2 = artifacts.require("QuotesV2");
const LiquidityBridgeContractV2 = artifacts.require('LiquidityBridgeContractV2.sol');
const BtcUtils = artifacts.require("BtcUtils");

const { read, deploy} = require("../config");

module.exports = async function (deployer, network, accounts) {
    let config = read();

    const signatureValidatorLib = await SignatureValidator.at(
        config[network]["SignatureValidator"].address
    );
    await deployer.link(signatureValidatorLib, LiquidityBridgeContractV2);

    await deployer.deploy(QuotesV2);
    const quotesInstance = await QuotesV2.deployed();
    await LiquidityBridgeContractV2.link("QuotesV2", quotesInstance.address);
    const quotesLib = await QuotesV2.at(
        quotesInstance.address
    );
    await deployer.link(quotesLib, LiquidityBridgeContractV2);

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
    } else if(network === 'rskTestnet') {
        daoFeeCollectorAddress = '0x86B6534687A176A476C16083a373fB9Fe4FAb449';
    }

    await response.initializeV2(1, daoFeeCollectorAddress);

    console.log("Upgraded", response.address);
};
