const { deployProxy } = require("@openzeppelin/truffle-upgrades");
const web3 = require("web3");

const LiquidityProviderContract = artifacts.require("LiquidityProviderContract");
const PeginContract = artifacts.require("PeginContract");
const PegoutContract = artifacts.require("PegoutContract");
const FlyoverUserContract = artifacts.require("FlyoverUserContract");
const FlyoverProviderContract = artifacts.require("FlyoverProviderContract");

const Mock = artifacts.require("Mock");
const BridgeMock = artifacts.require("BridgeMock");
const SignatureValidator = artifacts.require("SignatureValidator");
const Quotes = artifacts.require("Quotes");
const SignatureValidatorMock = artifacts.require("SignatureValidatorMock");
const BtcUtils = artifacts.require("BtcUtils");

const RSK_NETWORK_MAINNET = "rskMainnet";
const RSK_NETWORK_TESTNET = "rskTestnet";
const RSK_NETWORK_REGTEST = "rskRegtest";

const RSK_NETWORKS = [
  RSK_NETWORK_MAINNET,
  RSK_NETWORK_TESTNET,
  RSK_NETWORK_REGTEST,
];

const RSK_BRIDGE_ADDRESS = "0x0000000000000000000000000000000001000006";

const MINIMUM_COLLATERAL = "1"; // amount in wei
const MINIMUM_PEG_IN_DEFAULT = "5000000000000000"; // amount in wei
const MINIMUM_PEG_IN_REGTEST = "5000000000000000"; // amount in wei
const REWARD_PERCENTAGE = 10;
const RESIGN_DELAY_BLOCKS = 1;
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
      await deployer.link(SignatureValidator, PeginContract);
      await deployer.link(SignatureValidator, PegoutContract);
      const response = await SignatureValidator.deployed();
      state.address = response.address;
    });

    await deploy("Quotes", network, async (state) => {
      await deployer.deploy(Quotes);
      await deployer.link(Quotes, LiquidityProviderContract);
      await deployer.link(Quotes, FlyoverUserContract);
      await deployer.link(Quotes, FlyoverProviderContract);
      await deployer.link(Quotes, PeginContract);
      await deployer.link(Quotes, PegoutContract);
      const response = await Quotes.deployed();
      state.address = response.address;
    });

    await deploy("BtcUtils", network, async (state) => {
      await deployer.deploy(BtcUtils);
      await deployer.link(BtcUtils, PegoutContract);
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
      state.address = signatureValidatorMockInstance.address;
    });

    await deploy("Quotes", network, async (state) => {
      await deployer.deploy(Quotes);
      const quotesInstance = await Quotes.deployed();
      state.address = quotesInstance.address;
    });

    await deploy("BtcUtils", network, async (state) => {
      await deployer.deploy(BtcUtils);
      const btcUtilsInstance = await BtcUtils.deployed();
      state.address = btcUtilsInstance.address;
    });

    minimumPegIn = 2;
  }

  let config = read();

  config = await deploy("LiquidityProviderContract", network, async (state) => {
    const quotesLib = await Quotes.at(
      config[network]["Quotes"].address
    );
    await deployer.link(quotesLib, LiquidityProviderContract);

    const response = await deployProxy(
      LiquidityProviderContract,
      [
        bridgeAddress,
        MINIMUM_COLLATERAL,
        RESIGN_DELAY_BLOCKS,
        MAX_QUOTE_VALUE
      ],
      {
        deployer,
        unsafeAllowLinkedLibraries: true
      }
    );
    state.address = response.address;
  });

  config = await deploy("PegoutContract", network, async (state) => {
    const signatureValidatorLib = await SignatureValidator.at(
      config[network]["SignatureValidator"].address
    );
    await deployer.link(signatureValidatorLib, PegoutContract);

    const quotesLib = await Quotes.at(
      config[network]["Quotes"].address
    );
    await deployer.link(quotesLib, PegoutContract);

    const btcUtilsLib = await BtcUtils.at(
      config[network]["BtcUtils"].address
    );
    await deployer.link(btcUtilsLib, PegoutContract);

    const lpcAddress = config[network]["LiquidityProviderContract"].address;
    if (!lpcAddress) {
      throw new Error("There is no address for liquidity provider contract");
    }

    const response = await deployProxy(
      PegoutContract,
      [
        bridgeAddress,
        lpcAddress,
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

  config = await deploy("PeginContract", network, async (state) => {
    const signatureValidatorLib = await SignatureValidator.at(
      config[network]["SignatureValidator"].address
    );
    await deployer.link(signatureValidatorLib, PeginContract);

    const quotesLib = await Quotes.at(
      config[network]["Quotes"].address
    );
    await deployer.link(quotesLib, PeginContract);

    const btcUtilsLib = await BtcUtils.at(
      config[network]["BtcUtils"].address
    );
    await deployer.link(btcUtilsLib, PeginContract);

    const lpcAddress = config[network]["LiquidityProviderContract"].address;
    if (!lpcAddress) {
      throw new Error("There is no address for liquidity provider contract");
    }

    const response = await deployProxy(
      PeginContract,
      [
        bridgeAddress,
        lpcAddress,
        minimumPegIn,
        REWARD_PERCENTAGE,
        DUST_THRESHOLD
      ],
      {
        deployer,
        unsafeAllowLinkedLibraries: true
      }
    );
    state.address = response.address;
  });

  config = await deploy("FlyoverUserContract", network, async (state) => {
    const lpcAddress = config[network]["LiquidityProviderContract"].address;
    if (!lpcAddress) {
      throw new Error("There is no address for liquidity provider contract");
    }

    const pegoutContractAddress = config[network]["PegoutContract"].address;
    if (!lpcAddress) {
      throw new Error("There is no address for pegout contract");
    }

    const response = await deployProxy(
      FlyoverUserContract,
      [
        lpcAddress,
        pegoutContractAddress
      ],
      {
        deployer,
        unsafeAllowLinkedLibraries: true
      }
    );
    state.address = response.address;
  });

  config = await deploy("FlyoverProviderContract", network, async (state) => {
    const lpcAddress = config[network]["LiquidityProviderContract"].address;
    if (!lpcAddress) {
      throw new Error("There is no address for liquidity provider contract");
    }

    const pegoutContractAddress = config[network]["PegoutContract"].address;
    if (!lpcAddress) {
      throw new Error("There is no address for pegout contract");
    }

    const peginContractAddress = config[network]["PeginContract"].address;
    if (!lpcAddress) {
      throw new Error("There is no address for pegin contract");
    }

    const response = await deployProxy(
      FlyoverProviderContract,
      [
        lpcAddress,
        pegoutContractAddress,
        peginContractAddress
      ],
      {
        deployer,
        unsafeAllowLinkedLibraries: true
      }
    );
    await PeginContract.deployed().then(contract => contract.setProviderInterfaceAddress(response.address));
    await PegoutContract.deployed().then(contract => contract.setProviderInterfaceAddress(response.address));
    state.address = response.address;
  });
};
