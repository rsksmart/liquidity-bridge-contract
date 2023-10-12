const { upgradeProxy } = require("@openzeppelin/truffle-upgrades");

const SignatureValidator = artifacts.require("SignatureValidator");
const Quotes = artifacts.require("Quotes");
const LiquidityBridgeContract = artifacts.require('LiquidityBridgeContract');
const BtcUtils = artifacts.require("BtcUtils");

const { deploy, read } = require("../config");

module.exports = async function (deployer, network) {
    let config = read();
    config = await deploy("LiquidityBridgeContract", network, async (state) => {
        const signatureValidatorLib = await SignatureValidator.at(
            config[network]["SignatureValidator"].address
        );
        await deployer.link(signatureValidatorLib, LiquidityBridgeContract);

        const quotesLib = await Quotes.at(
            config[network]["Quotes"].address
        );
        await deployer.link(quotesLib, LiquidityBridgeContract);

        const btcUtilsLib = await BtcUtils.at(
            config[network]["BtcUtils"].address
        );
        await deployer.link(btcUtilsLib, LiquidityBridgeContract);

        const existing = config[network]["LiquidityBridgeContract"]
        const response = await upgradeProxy(
            existing.address,
            LiquidityBridgeContract,
            { deployer, unsafeAllowLinkedLibraries: true }
        );
        console.log("Upgraded", response.address);
        state.address = response.address;
    });
};
