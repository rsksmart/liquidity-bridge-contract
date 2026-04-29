import { task } from "hardhat/config";
import { DeploymentConfig, read } from "../scripts/deployment-utils/deploy";

task("get-versions")
  .setDescription(
    "Prints the versions of the LiquidityBridgeContract and its libraries where applicable"
  )
  .setAction(async (_, hre) => {
    const { ethers, network } = hre;
    const addresses: Partial<DeploymentConfig> = read();
    const networkDeployments: Partial<DeploymentConfig[string]> | undefined =
      addresses[network.name];

    if (!networkDeployments?.LiquidityBridgeContract?.address) {
      throw new Error(
        "LiquidityBridgeContract proxy deployment info not found"
      );
    }
    const lbcAddress = networkDeployments.LiquidityBridgeContract.address;

    if (!networkDeployments.BtcUtils?.address) {
      throw new Error(
        "LiquidityBridgeContract proxy deployment info not found"
      );
    }
    const btcUtilsAddress = networkDeployments.BtcUtils.address;

    const lbc = await ethers.getContractAt(
      "LiquidityBridgeContractV2",
      lbcAddress
    );
    const lbcVersion = await lbc.version().catch(() => "Not found");

    const btcUtils = await ethers.getContractAt("BtcUtils", btcUtilsAddress);
    const btcUtilsVersion = await btcUtils.version().catch(() => "Not found");

    console.info("=======================================");
    console.info(
      `LiquidityBridgeContract version: \x1b[32m${lbcVersion}\x1b[0m`
    );
    console.info(`BtcUtils version: \x1b[32m${btcUtilsVersion}\x1b[0m`);
    console.info("=======================================");
  });
