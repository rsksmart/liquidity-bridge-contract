import { ethers, upgrades } from "hardhat";
import { DeployedContractInfo, LOCAL_NETWORK, read } from "./deploy";
import { deployContract, REMOTE_NETWORKS } from "./utils";

interface LiquidityBridgeContractLibraries {
  quotesV2: string;
  btcUtils: string;
  signatureValidator: string;
}

export async function deployUpgradeLibraries(
  network: string,
  opts: { verbose: boolean }
): Promise<LiquidityBridgeContractLibraries> {
  let deployedSignatureValidator: Required<DeployedContractInfo>;
  if (opts.verbose) {
    console.info(`Deploying libraries in ${network}...`);
  }
  const quotesV2Deployment = await deployContract("QuotesV2", network);
  const btcUtilsDeployment = await deployContract("BtcUtils", network);
  if (REMOTE_NETWORKS.includes(network) || network === LOCAL_NETWORK) {
    deployedSignatureValidator = await deployContract(
      "SignatureValidator",
      network
    );
  } else {
    deployedSignatureValidator = await deployContract(
      "SignatureValidatorMock",
      network
    );
  }
  return {
    quotesV2: quotesV2Deployment.address,
    btcUtils: btcUtilsDeployment.address,
    signatureValidator: deployedSignatureValidator.address,
  };
}

/**
 * This function upgrades the LiquidityBridgeContract proxy contract to the LiquidityBridgeContractV2 version.
 * it upgrades the proxy whose address is under the key "LiquidityBridgeContract" in the addresses.json file.
 * It will also deploy and link the required libraries.
 *
 * @param network The network to deploy the contract to.
 * @param opts Options object, currently only has a verbose flag.
 *
 */
export async function upgradeLbcProxy(
  network: string,
  opts = { verbose: true }
) {
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
    console.info(`Upgrading proxy ${proxyAddress} with libs:`, libs);
  }
  const deployed = await upgrades
    .upgradeProxy(proxyAddress, LiquidityBridgeContractV2, {
      unsafeAllow: ["external-library-linking"],
    })
    .then((result) => result.waitForDeployment());
  const address = await deployed.getAddress();
  if (opts.verbose) {
    console.info(`Upgraded proxy at ${address}`);
  }
}
