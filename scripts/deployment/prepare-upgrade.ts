import hre from "hardhat";
import { deployLbcImplementation } from "../deployment-utils/deploy-lbc-implementation";

async function main() {
  const network = hre.network.name;
  const deploymentInfo = await deployLbcImplementation(network);
  console.info("IMPLEMENTATION ADDRESS: ", deploymentInfo.address);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
