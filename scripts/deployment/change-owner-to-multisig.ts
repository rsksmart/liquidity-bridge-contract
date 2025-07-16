import hre from "hardhat";
import { changeMultisigOwner } from "../deployment-utils/change-multisig-owner";
import multisigOwnersJson from "../../multisig-owners.json";

interface MultisigOwners {
  rskTestnet: { address: string; owners: string[] };
  rskMainnet: { address: string; owners: string[] };
  hardhat: { address: string; owners: string[] };
}

const multisigOwners: MultisigOwners = multisigOwnersJson;

async function main() {
  const network = hre.network.name as keyof MultisigOwners;
  const { address } = multisigOwners[network];
  if (!address || address === "") {
    throw new Error("Multisig address not found");
  }
  await changeMultisigOwner(address);
  console.info(
    `Ownership of LiquidityBridgeContract proxy changed to multisig in ${network}`
  );
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
