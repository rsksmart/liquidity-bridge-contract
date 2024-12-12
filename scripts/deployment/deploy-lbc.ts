import { deployLbcProxy } from "../deployment-utils/deploy-proxy";
import hre from "hardhat";

async function main() {
  const network = hre.network.name;
  const deployed = await deployLbcProxy(network);
  console.info(`LiquidityBridgeContract proxy successfully deployed in ${network} with address:`, deployed.address);
}

main()
.catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
