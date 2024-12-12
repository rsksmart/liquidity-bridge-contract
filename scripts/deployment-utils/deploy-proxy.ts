import { ethers, upgrades } from "hardhat";
import { deploy, DeployedContractInfo, LOCAL_NETWORK } from "./deploy";
import { deployContract, REMOTE_NETWORKS, TEST_NETWORKS } from "./utils";

interface LiquidityBridgeContractInitParams {
    bridgeAddress: string;
    minimumCollateral: bigint;
    minimumPegIn: bigint;
    rewardPercentage: number;
    resignDelayBlocks: number;
    dustThreshold: bigint;
    btcBlockTime: number;
    mainnet: boolean;
  }

  interface LiquidityBridgeContractLibraries {
    signatureValidator: string
    quotes: string
    btcUtils: string
    bridge: string
  }

const BRIDGE_ADDRESS = '0x0000000000000000000000000000000001000006';

async function deployProxyLibraries(network: string): Promise<LiquidityBridgeContractLibraries> {
  if (REMOTE_NETWORKS.includes(network) || network === LOCAL_NETWORK) {
    const quotesDeployment = await deployContract('Quotes', network);
    const btcUtilsDeployment = await deployContract('BtcUtils', network);
    const signatureValidatorDeployment = await deployContract('SignatureValidator', network);
    return {
      quotes: quotesDeployment.address,
      btcUtils: btcUtilsDeployment.address,
      signatureValidator: signatureValidatorDeployment.address,
      bridge: BRIDGE_ADDRESS,
    }
  } else {
    const quotesDeployment = await deployContract('Quotes', network);
    const btcUtilsDeployment = await deployContract('BtcUtils', network);
    const signatureValidatorMockDeployment = await deployContract('SignatureValidatorMock', network);
    const bridgeMockDeployment = await deployContract('BridgeMock', network);
    return {
      quotes: quotesDeployment.address,
      btcUtils: btcUtilsDeployment.address,
      signatureValidator: signatureValidatorMockDeployment.address,
      bridge: bridgeMockDeployment.address,
    }
  }
}

function getInitParameters(
  network:string,
  libraries: LiquidityBridgeContractLibraries,
): LiquidityBridgeContractInitParams {
  if (TEST_NETWORKS.includes(network)) {
    return {
      bridgeAddress: libraries.bridge,
      minimumCollateral: ethers.parseEther('0.03'),
      minimumPegIn: ethers.parseEther('0.5'),
      rewardPercentage: 10,
      resignDelayBlocks: 60,
      dustThreshold: 2300n * 65164000n,
      btcBlockTime: 900,
      mainnet: false
    }
  } else if (REMOTE_NETWORKS.includes(network)) {
    return {
      bridgeAddress: BRIDGE_ADDRESS,
      minimumCollateral: ethers.parseEther('0.03'),
      minimumPegIn: ethers.parseEther('0.005'),
      rewardPercentage: 10,
      resignDelayBlocks: 60,
      dustThreshold: 2300n * 65164000n,
      btcBlockTime: 900,
      mainnet: network === 'rskMainnet'
    }
  } else {
    throw new Error(`Network ${network} not supported`);
  }
}


export async function deployLbcProxy(network:string, opts = { verbose: true }): Promise<Required<DeployedContractInfo>> {
    const libs = await deployProxyLibraries(network);
    const proxyName = 'LiquidityBridgeContract';
    if (opts.verbose) {
        console.info(`Deploying proxy ${proxyName} with libs:`, libs);
    }
    const deployed = await deploy(proxyName, network, async () => {
      const LiquidityBridgeContract = await ethers.getContractFactory(proxyName, {
        libraries: {
          Quotes: libs.quotes,
          BtcUtils: libs.btcUtils,
          SignatureValidator: libs.signatureValidator
        }
      });
      const initParams = getInitParameters(network, libs);
      if (opts.verbose) {
        console.info('Initializing LBC with params:', initParams);
      }
      const deployed = await upgrades.deployProxy(
        LiquidityBridgeContract,
        [
          initParams.bridgeAddress,
          initParams.minimumCollateral,
          initParams.minimumPegIn,
          initParams.rewardPercentage,
          initParams.resignDelayBlocks,
          initParams.dustThreshold,
          initParams.btcBlockTime,
          initParams.mainnet,
        ],
        {
          unsafeAllow: [ 'external-library-linking' ],
        }
      ).then(result => result.waitForDeployment());
      const address = await deployed.getAddress();
      return address;
    });
    if (!deployed.deployed || !deployed.address) {
      throw new Error(`Error deploying proxy ${proxyName}`);
    }
    return { deployed: deployed.deployed, address: deployed.address };
}
