import { DeployedContractInfo } from "./deploy";
import { deployContract } from "./utils";

// TODO temporary map to resolve conflicts between legacy and split version.
// Should be removed once the legacy contracts are deleted
const CONFLICT_MAP: Record<string, string> = {
  Quotes: "contracts/libraries/Quotes.sol:Quotes",
};

export async function deployLibraries(
  network: string,
  ...libraries: ("Quotes" | "BtcUtils" | "SignatureValidator")[]
): Promise<Record<string, Required<DeployedContractInfo>>> {
  const result: Record<string, Required<DeployedContractInfo>> = {};
  const libSet = new Set(libraries);
  for (const lib of libSet) {
    const actualName = CONFLICT_MAP[lib] ?? lib;
    console.debug(`Deploying ${lib}...`);
    const deployment = await deployContract(actualName, network);
    result[lib] = deployment;
  }
  return result;
}
