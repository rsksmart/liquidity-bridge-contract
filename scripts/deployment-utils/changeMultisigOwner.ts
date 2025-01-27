import hre, { ethers } from "hardhat";
import { read } from "./deploy";
import multisigOwners from "../../multisig-owners.json";

export const changeMultisigOwner = async (newOowner: string) => {
  const network = hre.network.name;
  console.info(`Changing multisig owner to: ${newOowner} - ${network}`);

  const currentNetworkData =
    multisigOwners[network as keyof typeof multisigOwners];

  const { owners } = currentNetworkData;
  const proxyName = "LiquidityBridgeContract";

  const proxyAddress = read()[network][proxyName].address;
  if (!proxyAddress) {
    throw new Error(`Proxy ${proxyName} not deployed on network ${network}`);
  }
  console.info(`Proxy address: ${proxyAddress}`);

  const safeOwners = await validateAngGetOwners(newOowner);
  if (safeOwners.length === 0) {
    throw new Error(
      "Exiting... Provided Safe address is not a valid Safe contract."
    );
  }

  validateOwners(safeOwners, owners);

  console.info("Starting ownership transfer process...");
  await transferOwnership(proxyAddress, newOowner);
  console.log("Ownership transfer process complete!");
};

async function validateAngGetOwners(address: string): Promise<string[]> {
  try {
    const code = await ethers.provider.getCode(address);
    if (code === "0x") {
      throw new Error(`${address} is not a smart contract`);
    }
    const contract = await ethers.getContractAt("GnosisSafe", address);

    const version = await contract.VERSION();
    const owners = await contract.getOwners();
    if (owners.length === 0) {
      throw new Error("Owners array is empty");
    }
    console.info(`Address ${address} is a Safe contract! Version: ${version}`);

    return owners;
  } catch (error) {
    console.error(error);
    throw new Error(`Address ${address} Is not a Safe address`);
  }
}

function validateOwners(safeOwners: string[], expectedOwners: string[]): void {
  const safeSet = new Set(safeOwners.map((owner) => owner.toLowerCase()));
  const expectedSet = new Set(
    expectedOwners.map((owner) => owner.toLowerCase())
  );

  const isValid =
    safeSet.size === expectedSet.size &&
    [...safeSet].every((owner) => expectedSet.has(owner));
  if (isValid) {
    console.info(`Safe ownership matches expected configuration.`);
  } else {
    throw new Error(`Safe ownership does not match expected configuration.`);
  }
}

async function transferOwnership(
  proxyAddress: string,
  newOwnerAddress: string
): Promise<void> {
  try {
    const contract = await ethers.getContractAt(
      "LiquidityBridgeContractV2",
      proxyAddress
    );

    const currentOwner = await contract.owner();
    console.info(
      `Current owner of contract at ${proxyAddress}: ${currentOwner}`
    );

    if (currentOwner.toLowerCase() === newOwnerAddress.toLowerCase()) {
      console.info(
        `Ownership of contract at ${proxyAddress} is already set to ${newOwnerAddress}`
      );
      return;
    }

    console.log(
      `Transferring ownership of contract at ${proxyAddress} to ${newOwnerAddress}...`
    );
    await contract.transferOwnership(newOwnerAddress);

    console.log(
      `Ownership of contract at ${proxyAddress} successfully transferred to ${newOwnerAddress}!`
    );

    await hre.upgrades.admin.transferProxyAdminOwnership(
      proxyAddress,
      newOwnerAddress
    );
  } catch (error) {
    console.error(
      `Failed to transfer ownership of contract at ${proxyAddress}:`,
      error
    );
  }
}
