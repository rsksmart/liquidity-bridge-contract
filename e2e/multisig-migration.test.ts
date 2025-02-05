import { ethers } from "hardhat";
import * as helpers from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { changeMultisigOwner } from "../scripts/deployment-utils/change-multisig-owner";
import { expect } from "chai";
import { DeploymentConfig, read } from "../scripts/deployment-utils/deploy";
import multsigInfoJson from "../multisig-owners.json";

type MultisigInfo = Record<
  string,
  {
    address: string;
    owners?: string[];
  }
>;

const { FORK_NETWORK_NAME } = process.env;

const multsigInfo: MultisigInfo = multsigInfoJson;

describe("Should change LBC owner to the multisig", function () {
  it("Should change the owner", async () => {
    await checkForkedNetwork();

    const networkName = FORK_NETWORK_NAME ?? "rskTestnet";

    const addresses: Partial<DeploymentConfig> = read();
    const networkDeployments: Partial<DeploymentConfig[string]> | undefined =
      addresses[networkName];

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

    const safeAddress = multsigInfo[networkName].address;

    const lbcOwner = await lbc.owner();
    console.info("LBC owner:", lbcOwner);
    await helpers.impersonateAccount(lbcOwner);
    const impersonatedSigner = await ethers.getSigner(lbcOwner);

    await expect(
      changeMultisigOwner(safeAddress, "rskTestnet", impersonatedSigner)
    ).to.not.be.reverted;
    const newLbcOwner = await lbc.owner();
    console.info("New LBC owner:", newLbcOwner);
  });
});

async function checkForkedNetwork() {
  try {
    await ethers.provider.send("evm_snapshot", []);
  } catch (error) {
    console.error("Not a forked network:", error);
  }
}
