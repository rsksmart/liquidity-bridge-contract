import hre, { ethers } from "hardhat";
import { read } from "./deploy";
import multisigOwners from "../../multisig-owners.json";

/**
 * Changes the multisig owner of the `LiquidityBridgeContract` deployed on the current network to the safe wallet
 * provided.
 *
 * This function validates the provided `newOwner` address, ensures ownership configuration matches
 * expectations, and performs the transfer of ownership to the new multisig address. Additionally,
 * it updates both the contract and proxy admin ownership.
 *
 * @async
 * @param {string} newOwner - The address of the new multisig owner (Safe contract).
 * @throws {Error} If the proxy contract is not deployed on the current network.
 * @throws {Error} If the provided `newOwner` address is not a valid multisig Safe contract.
 * @throws {Error} If the configuration of owners on the Safe does not match the expected configuration.
 * @returns {Promise<void>} Resolves when the ownership transfer process is complete.
 *
 * @example
 * // Change the multisig owner of the contract
 * const newMultisigAddress = "0xNewSafeAddress";
 * await changeMultisigOwner(newMultisigAddress);
 */

export const changeMultisigOwner = async (newOwner: string) => {
  const network = hre.network.name;
  console.info(`Changing multisig owner to: ${newOwner} - ${network}`);

  const currentNetworkData =
    multisigOwners[network as keyof typeof multisigOwners];

  const { owners } = currentNetworkData;
  const proxyName = "LiquidityBridgeContract";

  const proxyAddress = read()[network][proxyName].address;
  if (!proxyAddress) {
    throw new Error(`Proxy ${proxyName} not deployed on network ${network}`);
  }
  console.info(`Proxy address: ${proxyAddress}`);

  const safeOwners = await validateAndGetOwners(newOwner);
  if (safeOwners.length === 0) {
    throw new Error(
      "Exiting... Provided Safe address is not a valid Safe contract."
    );
  }

  validateOwners(safeOwners, owners);

  console.info("Starting ownership transfer process...");
  await transferOwnership(proxyAddress, newOwner);
  console.info("Ownership transfer process complete!");
};

async function validateAndGetOwners(address: string): Promise<string[]> {
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

    console.info(
      `Transferring ownership of contract at ${proxyAddress} to ${newOwnerAddress}...`
    );
    await contract.transferOwnership(newOwnerAddress);

    console.info(
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
