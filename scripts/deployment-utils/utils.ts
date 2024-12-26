import { ethers } from "hardhat";
import { deploy, DeployedContractInfo, LOCAL_NETWORK } from "./deploy";

export const TEST_NETWORKS = ["localhost", "hardhat", "ganache", LOCAL_NETWORK];

export const REMOTE_NETWORKS = ["rskDevelopment", "rskTestnet", "rskMainnet"];

/**
 * This function wraps the {@link deploy} function to deploy a contract using ethers.js
 * and save the results in the addresses.json file.
 *
 * @param contract The name of the contract to deploy, as it appears in the addresses.json file.
 * @param network The name of the network as it appears in the addresses.json file.
 * @returns { Required<DeployedContractInfo> } The information of the deployed contract.
 */
export async function deployContract(
  contract: string,
  network: string
): Promise<Required<DeployedContractInfo>> {
  const deploymentInfo = await deploy(contract, network, async () => {
    const contractFactory = await ethers.getContractFactory(contract);
    const contractDeployment = await contractFactory.deploy();
    const deployedContract = await contractDeployment.waitForDeployment();
    const address = await deployedContract.getAddress();
    return address;
  });
  if (!deploymentInfo.deployed || !deploymentInfo.address) {
    throw new Error(`Error deploying ${contract}`);
  }
  return { deployed: deploymentInfo.deployed, address: deploymentInfo.address };
}
