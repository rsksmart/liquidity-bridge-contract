const { deployProxy } = require("@openzeppelin/truffle-upgrades");
const web3 = require("web3");

const LiquidityBridgeContract = artifacts.require("LiquidityBridgeContract");

const Mock = artifacts.require("Mock");
const BridgeMock = artifacts.require("BridgeMock");
const SignatureValidator = artifacts.require("SignatureValidator");
const Quotes = artifacts.require("Quotes");
const SignatureValidatorMock = artifacts.require("SignatureValidatorMock");
const BtcUtils = artifacts.require("BtcUtils");

const RSK_NETWORK_MAINNET = "rskMainnet";
const RSK_NETWORK_TESTNET = "rskTestnet";
const RSK_NETWORK_REGTEST = "rskRegtest";
const INTERNAL_ALPHANET = "alphanet";

const RSK_NETWORKS = [
  RSK_NETWORK_MAINNET,
  RSK_NETWORK_TESTNET,
  RSK_NETWORK_REGTEST,
  INTERNAL_ALPHANET
];

const RSK_BRIDGE_ADDRESS = "0x0000000000000000000000000000000001000006";

const MINIMUM_COLLATERAL = "600000000000000000"; // amount in wei
const MINIMUM_PEG_IN_DEFAULT = "5000000000000000"; // amount in wei
const MINIMUM_PEG_IN_REGTEST = "5000000000000000"; // amount in wei
const REWARD_PERCENTAGE = 10;
const RESIGN_DELAY_BLOCKS = 15;
const DUST_THRESHOLD = 2300 * 65164000;
const MAX_QUOTE_VALUE = web3.utils.toBN("1000000000000000000"); // amount in wei
const BTC_BLOCK_TIME = 5400; // the 5400 addition is to give 1.5h to the tx to be mined
const { deploy, read } = require("../config");

module.exports = async function (deployer, network) {
  let minimumPegIn, bridgeAddress;
  const mainnet = network === RSK_NETWORK_MAINNET;
  if (RSK_NETWORKS.includes(network)) {
    // deploy to actual networks so don't use mocks and use existing bridge.
    bridgeAddress = RSK_BRIDGE_ADDRESS;

    await deploy("SignatureValidator", network, async (state) => {
      await deployer.deploy(SignatureValidator);
      await deployer.link(SignatureValidator, LiquidityBridgeContract);
      const response = await SignatureValidator.deployed();
      state.address = response.address;
    });

    await deploy("Quotes", network, async (state) => {
      await deployer.deploy(Quotes);
      await deployer.link(Quotes, LiquidityBridgeContract);
      const response = await Quotes.deployed();
      state.address = response.address;
    });

    await deploy("BtcUtils", network, async (state) => {
      await deployer.deploy(BtcUtils);
      await deployer.link(BtcUtils, LiquidityBridgeContract);
      const response = await BtcUtils.deployed();
      state.address = response.address;
    });

    if (network === RSK_NETWORK_REGTEST) {
      minimumPegIn = MINIMUM_PEG_IN_REGTEST;
    } else {
      minimumPegIn = MINIMUM_PEG_IN_DEFAULT;
    }
  } else {
    // test with mocks;
    await deployer.deploy(Mock);

    await deployer.deploy(BridgeMock);
    const bridgeMockInstance = await BridgeMock.deployed();
    bridgeAddress = bridgeMockInstance.address;

    await deploy("SignatureValidator", network, async (state) => {
      await deployer.deploy(SignatureValidatorMock);
      const signatureValidatorMockInstance =
        await SignatureValidatorMock.deployed();
      await LiquidityBridgeContract.link(
        "SignatureValidator",
        signatureValidatorMockInstance.address
      );
      state.address = signatureValidatorMockInstance.address;
    });

    await deploy("Quotes", network, async (state) => {
      await deployer.deploy(Quotes);
      const quotesInstance = await Quotes.deployed();
      await LiquidityBridgeContract.link("Quotes", quotesInstance.address);
      state.address = quotesInstance.address;
    });

    await deploy("BtcUtils", network, async (state) => {
      await deployer.deploy(BtcUtils);
      const btcUtilsInstance = await BtcUtils.deployed();
      await LiquidityBridgeContract.link("BtcUtils", btcUtilsInstance.address);
      state.address = btcUtilsInstance.address;
    });

    minimumPegIn = 2;
  }

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

    
    const response = await deployProxy(
      LiquidityBridgeContract,
      [
        bridgeAddress,
        MINIMUM_COLLATERAL,
        minimumPegIn,
        REWARD_PERCENTAGE,
        RESIGN_DELAY_BLOCKS,
        DUST_THRESHOLD,
        MAX_QUOTE_VALUE,
        BTC_BLOCK_TIME,
        mainnet
      ],
      {
        deployer,
        unsafeAllowLinkedLibraries: true
      }
    );
    state.address = response.address;
  });
};
