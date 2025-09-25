/* eslint-disable @typescript-eslint/no-unsafe-assignment */
/* eslint-disable @typescript-eslint/no-unsafe-member-access */
/* eslint-disable @typescript-eslint/no-unsafe-call */
/* eslint-disable @typescript-eslint/restrict-template-expressions */
/* eslint-disable @typescript-eslint/prefer-nullish-coalescing */
/* eslint-disable @typescript-eslint/dot-notation */
/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable @typescript-eslint/no-confusing-void-expression */

import { task, types } from "hardhat/config";
import { DeploymentConfig, read } from "../scripts/deployment-utils/deploy";

interface ContractInfo {
  name: string;
  address: string;
  contractName: string;
}

task("pause-system")
  .setDescription(
    "Pause/unpause all Flyover system contracts simultaneously (FlyoverDiscovery, PegInContract, PegOutContract, CollateralManagement)"
  )
  .addParam(
    "action",
    "Action to perform: 'pause' or 'unpause'",
    undefined,
    types.string
  )
  .addOptionalParam(
    "reason",
    "Reason for pausing (required when action=pause)",
    undefined,
    types.string
  )
  .addOptionalParam(
    "pauser",
    "Address of the account with PAUSER_ROLE (defaults to first signer)",
    undefined,
    types.string
  )
  .setAction(async (args, hre) => {
    const { ethers, network } = hre;
    const typedArgs = args as {
      action: string;
      reason?: string;
      pauser?: string;
    };

    const action = typedArgs.action.toLowerCase();
    const reason = typedArgs.reason;
    const pauserAddress = typedArgs.pauser;

    // Validate inputs
    if (!["pause", "unpause"].includes(action)) {
      throw new Error("Action must be 'pause' or 'unpause'");
    }

    if (action === "pause" && !reason) {
      throw new Error("Reason parameter is required when pausing");
    }

    console.info(
      `🚀 ${action.toUpperCase()} operation starting on network: ${
        network.name
      }`
    );
    if (action === "pause") {
      console.info(`📝 Reason: ${reason}`);
    }

    // Get deployed contract addresses
    const addresses: Partial<DeploymentConfig> = read();
    const networkDeployments: Partial<DeploymentConfig[string]> | undefined =
      addresses[network.name];

    if (!networkDeployments) {
      throw new Error(
        `No deployment config found for network: ${network.name}`
      );
    }

    const contracts: ContractInfo[] = [
      {
        name: "FlyoverDiscovery",
        address: networkDeployments["FlyoverDiscovery"]?.address || "",
        contractName: "FlyoverDiscovery",
      },
      {
        name: "PegInContract",
        address: networkDeployments["PegInContract"]?.address || "",
        contractName: "PegInContract",
      },
      {
        name: "PegOutContract",
        address: networkDeployments["PegOutContract"]?.address || "",
        contractName: "PegOutContract",
      },
      {
        name: "CollateralManagementContract",
        address:
          networkDeployments["CollateralManagementContract"]?.address || "",
        contractName: "CollateralManagementContract",
      },
    ];

    // Validate all contracts are deployed
    const missingContracts = contracts.filter((c) => !c.address);
    if (missingContracts.length > 0) {
      throw new Error(
        `Missing contract addresses for: ${missingContracts
          .map((c) => c.name)
          .join(", ")}`
      );
    }

    // Get signer
    const signers = await ethers.getSigners();
    let signer = signers[0];

    if (pauserAddress) {
      // Use specific pauser address if provided
      signer = await ethers.getSigner(pauserAddress);
    }

    console.info(`👤 Using account: ${signer.address}`);

    // Check pause status before operation
    console.info("\n📊 Current pause status:");
    for (const contract of contracts) {
      const contractInstance = await ethers.getContractAt(
        contract.contractName,
        contract.address
      );
      const pauseStatus = await contractInstance.pauseStatus();
      console.info(
        `  ${contract.name}: ${pauseStatus.isPaused ? "PAUSED" : "ACTIVE"}`
      );
      if (pauseStatus.isPaused) {
        console.info(`    - Reason: ${pauseStatus.reason}`);
        console.info(
          `    - Since: ${new Date(
            Number(pauseStatus.since) * 1000
          ).toISOString()}`
        );
      }
    }

    // Execute pause/unpause operation
    console.info(`\n🔄 Executing ${action} operation...`);
    const results: {
      contract: string;
      success: boolean;
      txHash?: string;
      error?: string;
    }[] = [];

    for (const contract of contracts) {
      try {
        console.info(`  Processing ${contract.name}...`);
        const contractInstance = await ethers.getContractAt(
          contract.contractName,
          contract.address
        );

        let tx;
        if (action === "pause") {
          tx = await contractInstance.connect(signer).pause(reason!);
        } else {
          tx = await contractInstance.connect(signer).unpause();
        }

        const receipt = await tx.wait();
        results.push({
          contract: contract.name,
          success: true,
          txHash: receipt!.hash,
        });
        console.info(
          `    ✅ ${contract.name} ${action}d successfully - TX: ${
            receipt!.hash
          }`
        );
      } catch (error: any) {
        results.push({
          contract: contract.name,
          success: false,
          error: error.message,
        });
        console.info(
          `    ❌ Failed to ${action} ${contract.name}: ${error.message}`
        );
      }
    }

    // Summary
    console.info(`\n📋 Operation Summary:`);
    const successful = results.filter((r) => r.success);
    const failed = results.filter((r) => !r.success);

    console.info(`  ✅ Successful: ${successful.length}/${results.length}`);
    successful.forEach((r) => console.info(`    - ${r.contract}: ${r.txHash}`));

    if (failed.length > 0) {
      console.info(`  ❌ Failed: ${failed.length}/${results.length}`);
      failed.forEach((r) => console.info(`    - ${r.contract}: ${r.error}`));
    }

    // Final status check
    console.info("\n📊 Final pause status:");
    for (const contract of contracts) {
      const contractInstance = await ethers.getContractAt(
        contract.contractName,
        contract.address
      );
      const pauseStatus = await contractInstance.pauseStatus();
      console.info(
        `  ${contract.name}: ${pauseStatus.isPaused ? "PAUSED" : "ACTIVE"}`
      );
      if (pauseStatus.isPaused) {
        console.info(`    - Reason: ${pauseStatus.reason}`);
        console.info(
          `    - Since: ${new Date(
            Number(pauseStatus.since) * 1000
          ).toISOString()}`
        );
      }
    }

    if (failed.length > 0) {
      throw new Error(`${action} operation failed for some contracts`);
    }

    console.info(
      `\n🎉 ${action.toUpperCase()} operation completed successfully!`
    );
  });
