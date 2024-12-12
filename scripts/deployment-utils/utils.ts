import { ethers } from "hardhat";
import { deploy, DeployedContractInfo, LOCAL_NETWORK } from "./deploy";

export const TEST_NETWORKS = ['localhost', 'hardhat', 'ganache', LOCAL_NETWORK];

export const REMOTE_NETWORKS = ['rskDevelopment', 'rskTestnet', 'rskMainnet'];

export async function deployContract(contract: string, network: string): Promise<Required<DeployedContractInfo>> {
    const deploymentInfo = await deploy(contract, network, async () => {
        const contractFactory = await ethers.getContractFactory(contract);
        const contractDeployment = await contractFactory.deploy();
        const deployedContract = await contractDeployment.waitForDeployment();
        const address = await deployedContract.getAddress();
        return address
    });
    if (!deploymentInfo.deployed || !deploymentInfo.address) {
        throw new Error(`Error deploying ${contract}`);
    }
    return { deployed: deploymentInfo.deployed, address: deploymentInfo.address };
}
