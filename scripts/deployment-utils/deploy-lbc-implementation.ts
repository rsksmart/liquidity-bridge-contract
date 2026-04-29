import { ethers, upgrades } from "hardhat";
import { DeployedContractInfo, read } from "./deploy";
import { deployUpgradeLibraries } from "./upgrade-proxy";

/**
 * This function deploys a LBC implementation contract **without** redirecting the LBC proxy. This function
 * should be used when the deployment of the implementation contract is not going to be performed by the
 * proxy admin owner. The deployment includes deploying the required libraries and linking them to the contract.
 *
 * @param network The name of the network to deploy the contract to as it appears in the addresses.json file.
 * @param opts Options object, currently only has a verbose flag.
 *
 * @returns { Promise<DeployedContractInfo> } The information of the deployed contract.
 */
export async function deployLbcImplementation(
  network: string,
  opts = { verbose: true }
): Promise<Required<DeployedContractInfo>> {
  const libs = await deployUpgradeLibraries(network, opts);
  const proxyName = "LiquidityBridgeContract";
  const upgradeName = "LiquidityBridgeContractV2";
  const LiquidityBridgeContractV2 = await ethers.getContractFactory(
    upgradeName,
    {
      libraries: {
        QuotesV2: libs.quotesV2,
        BtcUtils: libs.btcUtils,
        SignatureValidator: libs.signatureValidator,
      },
    }
  );

  const proxyAddress = read()[network][proxyName].address;
  if (!proxyAddress) {
    throw new Error(`Proxy ${proxyName} not deployed on network ${network}`);
  }

  if (opts.verbose) {
    console.info(`Deploying implementation with libs:`, libs);
  }

  await upgrades.validateUpgrade(proxyAddress, LiquidityBridgeContractV2, {
    unsafeAllow: ["external-library-linking"],
  });
  const implementationAddress = (await upgrades.prepareUpgrade(
    proxyAddress,
    LiquidityBridgeContractV2,
    {
      unsafeAllow: ["external-library-linking"],
    }
  )) as string;
  if (opts.verbose) {
    console.info(`Implementation deployed at ${implementationAddress}`);
  }

  return {
    deployed: true,
    address: implementationAddress,
  };
}
