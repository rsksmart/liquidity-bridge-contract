import { task, types } from "hardhat/config";
import { DeploymentConfig, read } from "../scripts/deployment-utils/deploy";

task("refund-user-pegout")
  .setDescription(
    "Refund a user that didn't receive their PegOut in the agreed time"
  )
  .addParam(
    "quotehash",
    "The hash of the accepted PegOut quote",
    undefined,
    types.string
  )
  .setAction(async (args, hre) => {
    const { ethers, network } = hre;
    const typedArgs = args as { quotehash: string };
    const quoteHash: string = "0x" + typedArgs.quotehash;

    const addresses: Partial<DeploymentConfig> = read();
    const networkDeployments: Partial<DeploymentConfig[string]> | undefined =
      addresses[network.name];

    const lbcAddress = networkDeployments?.LiquidityBridgeContract?.address;
    if (!lbcAddress) {
      throw new Error(
        "LiquidityBridgeContract proxy deployment info not found"
      );
    }
    const lbc = await ethers.getContractAt(
      "LiquidityBridgeContractV2",
      lbcAddress
    );

    const gasEstimation = await lbc.refundUserPegOut.estimateGas(quoteHash);
    console.info("Gas estimation for refundUserPegOut:", gasEstimation);

    const tx = await lbc.refundUserPegOut(quoteHash);
    const receipt = await tx.wait();
    console.info(`Transaction hash: ${receipt!.hash}`);
    console.info("Transaction receipt: ");
    console.info(receipt);
  });
