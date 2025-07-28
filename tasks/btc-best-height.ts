import { task } from "hardhat/config";
import { BRIDGE_ADDRESS } from "../scripts/deployment-utils/constants";

task("btc-best-height")
  .setDescription(
    "Prints the best height of the Bitcoin network seen by the Rootstock Bridge"
  )
  .setAction(async (_, hre) => {
    const { ethers } = hre;
    const bridge = await ethers.getContractAt("IBridge", BRIDGE_ADDRESS);
    const bestHeight = await bridge.getBtcBlockchainBestChainHeight();
    console.info(
      `Best BTC blockchain height: \x1b[32m${bestHeight.toString()}\x1b[0m`
    );
  });
