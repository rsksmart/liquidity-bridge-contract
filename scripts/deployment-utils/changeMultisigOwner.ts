import hre from "hardhat";
import { ethers } from "ethers";
import * as dotenv from "dotenv";
import networkData from "../../networkData.json";

dotenv.config();

const SafeABI = [
  "function VERSION() view returns (string)",
  "function getOwners() view returns (address[])",
];

const OwnableABI = [
  "function owner() view returns (address)",
  "function transferOwnership(address newOwner)",
];

async function main() {
  const network = hre.network.name;
  const address = "";
  console.log(`Changing multisig owner to: ${address} - ${network}`);

  const currentNetworkData = networkData[network as keyof typeof networkData];

  const { owners, lbcProxyAddress, lbcProxyAdminAddress } = currentNetworkData;

  const etherProvider = new ethers.JsonRpcProvider(
    currentNetworkData.providerRpc
  );

  const isSafe = await isSafeAddress(etherProvider, address);
  if (!isSafe) {
    console.error(
      "Exiting... Provided Safe address is not a valid Safe contract."
    );
    return;
  }

  const safeOwners = await getOwners(etherProvider, address);
  if (!validateOwners(safeOwners, owners)) {
    console.error(
      "Exiting... Safe owners do not match expected configuration."
    );
    return;
  }

  const signer = ethers.Wallet.fromPhrase(
    currentNetworkData.mnemonic,
    etherProvider
  );

  console.log("Starting ownership transfer process...");

  await transferOwnership(signer, lbcProxyAddress, address);
  await transferOwnership(signer, lbcProxyAdminAddress, address);

  console.log("Ownership transfer process complete!");
}

async function isSafeAddress(
  provider: ethers.JsonRpcProvider,
  address: string
): Promise<boolean> {
  try {
    const code = await provider.getCode(address);
    if (code === "0x") {
      console.log(`${address} is not a smart contract`);
      return false;
    }
    const contract = new ethers.Contract(address, SafeABI, provider);

    const version = (await contract.VERSION()) as string;
    console.log(`Address ${address} is a Safe contract! Version: ${version}`);

    return true;
  } catch (error) {
    console.error(`Address ${address} Is not a Safe address.`, error);
    return false;
  }
}

async function getOwners(
  provider: ethers.JsonRpcProvider,
  address: string
): Promise<string[]> {
  try {
    const contract = new ethers.Contract(address, SafeABI, provider);
    const owners = (await contract.getOwners()) as string[];
    console.log(`Owners of Safe Contract at ${address}:`, owners);
    return owners;
  } catch (error) {
    console.error(`Failed to get owners for address ${address}:`, error);
    return [];
  }
}

function validateOwners(
  safeOwners: string[],
  expectedOwners: string[]
): boolean {
  const safeSet = new Set(safeOwners.map((owner) => owner.toLowerCase()));
  const expectedSet = new Set(
    expectedOwners.map((owner) => owner.toLowerCase())
  );

  const isValid =
    safeSet.size === expectedSet.size &&
    [...safeSet].every((owner) => expectedSet.has(owner));
  if (isValid) {
    console.log(`Safe ownership matches expected configuration.`);
  } else {
    console.error(`Safe ownership does not match expected configuration.`);
  }

  return isValid;
}

async function transferOwnership(
  signer: ethers.HDNodeWallet,
  contractAddress: string,
  newOwnerAddress: string
): Promise<void> {
  try {
    const contract = new ethers.Contract(contractAddress, OwnableABI, signer);

    const currentOwner = (await contract.owner()) as string;
    console.log(
      `Current owner of contract at ${contractAddress}: ${currentOwner}`
    );

    if (currentOwner.toLowerCase() === newOwnerAddress.toLowerCase()) {
      console.log(
        `Ownership of contract at ${contractAddress} is already set to ${newOwnerAddress}`
      );
      return;
    }

    console.log(
      `Transferring ownership of contract at ${contractAddress} to ${newOwnerAddress}...`
    );
    await contract.transferOwnership(newOwnerAddress);

    console.log(
      `Ownership of contract at ${contractAddress} successfully transferred to ${newOwnerAddress}!`
    );
  } catch (error) {
    console.error(
      `Failed to transfer ownership of contract at ${contractAddress}:`,
      error
    );
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
