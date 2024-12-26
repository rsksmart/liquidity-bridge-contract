import hre from "hardhat";
import { upgradeLbcProxy } from "../deployment-utils/upgrade-proxy";

async function main() {
  const network = hre.network.name;
  await upgradeLbcProxy(network);
  console.info("LiquidityBridgeContract proxy upgraded successfully");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
